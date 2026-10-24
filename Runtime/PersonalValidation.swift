#if os(iOS) && MYNOOP_PERSONAL
import Foundation
import SwiftUI
import Security
import CryptoKit
import AuthenticationServices
import UIKit
import StrandAnalytics
import StrandDesign

// Personal iPhone-only validation lane. Reference scores never enter WhoopStore or its baselines.
@MainActor
final class PersonalValidation: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PersonalValidation()
    static let preference = "personal.validation.enabled"

    struct Connection: Codable {
        let origin: URL
        let ownerToken: String
    }
    struct Metric: Decodable { let n: Int; let mae: Double?; let bias: Double? }
    struct Group: Decodable, Identifiable {
        let device: String
        let algorithm: String
        let observations: Int
        let matched: Int
        let unmatched: Int
        let ambiguous: Int
        let quality_excluded: Int
        let reference_nights: Int
        let metrics: [String: Metric]
        var id: String { device + algorithm }
    }
    struct Report: Decodable {
        struct Sync: Decodable { let last_success: Double; let error: String? }
        struct Policy: Decodable { let kind: String }
        let connected: Bool
        let sync: Sync
        let evaluation_policy: Policy
        let groups: [Group]
    }
    private struct Authorization: Decodable { let authorization_url: URL }
    enum Failure: Error { case configuration, response, cancelled }

    @Published private(set) var report: Report?
    @Published private(set) var busy = false
    @Published private(set) var failed = false
    @Published private(set) var configured = false
    @Published private(set) var lastUpload: Date?
    private var webSession: ASWebAuthenticationSession?
    private var lastAttempt = Date.distantPast
    private var displayedSource: String?
    private var generation = 0
    private var session = PersonalValidation.makeSession()
    private static let keychainService = "app.m1.safw.validation"

    override init() {
        super.init()
        refreshConfiguration()
    }

    func refreshConfiguration() { configured = (try? connection()) != nil }

    nonisolated private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 90
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config, delegate: ValidationTransport(), delegateQueue: nil)
    }

    private func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.keychainService,
         kSecAttrAccount as String: "owner-connection"]
    }

    func connection() throws -> Connection {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { throw Failure.configuration }
        return try JSONDecoder().decode(Connection.self, from: data)
    }

    func save(origin: String, token: String) throws {
        guard let parts = URLComponents(string: origin.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", parts.host != nil, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, ["", "/"].contains(parts.path),
              let url = parts.url, token.count >= 32, !token.contains(where: { $0.isWhitespace })
        else { throw Failure.configuration }
        let data = try JSONEncoder().encode(Connection(origin: url, ownerToken: token))
        var attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let result = SecItemUpdate(query() as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            attributes.merge(query()) { current, _ in current }
            guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw Failure.configuration }
        } else if result != errSecSuccess { throw Failure.configuration }
        generation += 1
        session.invalidateAndCancel()
        session = Self.makeSession()
        report = nil
        lastUpload = nil
        lastAttempt = .distantPast
        configured = true
        failed = false
    }

    func suspend() {
        generation += 1
        session.invalidateAndCancel()
        session = Self.makeSession()
        webSession?.cancel()
        webSession = nil
        PersonalValidationScheduler.updateSchedule()
    }

    private func request(_ path: String, connection: Connection, method: String = "GET", body: Data? = nil) async throws -> Data {
        let url = connection.origin.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer " + connection.ownerToken, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 2 * 1024 * 1024 else { throw Failure.response }
        return data
    }

    func connect() async {
        guard !busy, UserDefaults.standard.bool(forKey: Self.preference) else { return }
        busy = true
        failed = false
        let current = generation
        defer { busy = false }
        do {
            let connection = try connection()
            let data = try await request("v1/connect", connection: connection, method: "POST")
            let auth = try JSONDecoder().decode(Authorization.self, from: data)
            // A paired receiver may supply authorization parameters, never an arbitrary login host.
            guard auth.authorization_url.scheme == "https",
                  auth.authorization_url.host == "api.prod.whoop.com",
                  auth.authorization_url.path == "/oauth/oauth2/auth",
                  current == generation else { throw Failure.response }
            try await authorize(auth.authorization_url)
            guard current == generation, UserDefaults.standard.bool(forKey: Self.preference) else { return }
            let result = try await request("v1/report", connection: connection)
            guard current == generation else { return }
            report = try JSONDecoder().decode(Report.self, from: result)
            guard report?.evaluation_policy.kind == "first_timely_upload" else {
                report = nil
                throw Failure.response
            }
            if report?.connected != true { throw Failure.response }
            lastAttempt = .distantPast
        } catch {
            if current == generation { failed = true }
        }
    }

    private func authorize(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: "safw-validation") { result, error in
                guard error == nil, result?.scheme == "safw-validation", result?.host == "complete" else {
                    continuation.resume(throwing: Failure.cancelled)
                    return
                }
                continuation.resume()
            }
            auth.presentationContextProvider = self
            auth.prefersEphemeralWebBrowserSession = false
            webSession = auth
            if !auth.start() {
                webSession = nil
                continuation.resume(throwing: Failure.cancelled)
            }
        }
        webSession = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    func synchronize(repo: Repository, force: Bool = false) async -> Bool {
        guard UserDefaults.standard.bool(forKey: Self.preference), !busy else { return true }
        if displayedSource != repo.deviceId {
            displayedSource = repo.deviceId
            report = nil
            lastUpload = nil
            lastAttempt = .distantPast
        }
        let storedConnection: Connection
        do { storedConnection = try connection(); configured = true }
        catch { configured = false; failed = true; return false }
        guard force || Date().timeIntervalSince(lastAttempt) >= 15 * 60 else { return true }
        busy = true
        lastAttempt = Date()
        failed = false
        let current = generation
        let source = repo.deviceId
        defer { busy = false }
        do {
            let now = Int(Date().timeIntervalSince1970)
            var rows: [[String: Any]] = []
            if repo.activeStrapIsWhoop5(), let store = await repo.storeHandle() {
                let computed = source + "-noop"
                // No dashboard/union read: those intentionally prefer the imported WHOOP result.
                let start = Date(timeIntervalSince1970: Double(now - 90 * 86400))
                let daily = try await store.dailyMetrics(deviceId: computed,
                    from: Repository.localDayKey(start), to: Repository.localDayKey(Date()))
                let byDay = Dictionary(daily.map { ($0.day, $0) }, uniquingKeysWith: { _, newer in newer })
                let sleeps = try await store.sleepSessions(deviceId: computed, from: now - 90 * 86400, to: now, limit: 200)
                let device = Self.digest(source)
                let algorithm = Self.algorithmID()
                for sleep in sleeps.suffix(200) where sleep.endTs <= now - 3600 && sleep.endTs > sleep.effectiveStartTs {
                    // Imported stage-total dictionaries cannot masquerade as locally staged segments.
                    guard sleep.endTs - sleep.effectiveStartTs <= 24 * 3600 else { continue }
                    let bytes = sleep.stagesJSON?.data(using: .utf8)
                    let isSegments = bytes.flatMap { try? JSONSerialization.jsonObject(with: $0) } is [[String: Any]]
                    let stages = isSegments ? SleepStageTotals.minutes(fromStagesJSON: sleep.stagesJSON) : nil
                    let day = Repository.localDayKey(Date(timeIntervalSince1970: Double(sleep.endTs)))
                    let metric = byDay[day]
                    let owner = try await store.scoreInputSource(deviceId: computed, day: day, key: "recovery")
                    // Recovery is a daily result: only one main block may claim it; fragmented or
                    // ambiguous nights remain in the sleep report but do not inflate recovery agreement.
                    let sameDay = sleeps.filter {
                        Repository.localDayKey(Date(timeIntervalSince1970: Double($0.endTs))) == day
                            && $0.endTs - $0.effectiveStartTs >= 3 * 3600
                    }
                    let locallyMeasured = owner == source && sameDay.count == 1 &&
                        sameDay.first?.startTs == sleep.startTs && metric?.avgHrv != nil
                    func value(_ n: Double?) -> Any {
                        guard let n, n.isFinite else { return NSNull() }
                        return n
                    }
                    rows.append(["device": device, "algorithm": algorithm,
                        "start": sleep.effectiveStartTs, "end": sleep.endTs, "captured_at": now,
                        "recovery": value(locallyMeasured ? metric?.recovery : nil),
                        "hrv": value(locallyMeasured ? metric?.avgHrv : nil),
                        "rhr": value(locallyMeasured ? metric?.restingHr.map { Double($0) } : nil),
                        "light": value(stages?.light), "deep": value(stages?.deep),
                        "rem": value(stages?.rem), "awake": value(stages?.awake),
                        "sparse": sleep.stagingSparse != false || stages == nil, "user_edited": sleep.userEdited,
                        "local_recovery_input": locallyMeasured])
                }
            }
            guard !Task.isCancelled, current == generation, repo.deviceId == source,
                  UserDefaults.standard.bool(forKey: Self.preference) else { return false }
            let body = try JSONSerialization.data(withJSONObject: ["observations": rows], options: [.sortedKeys])
            let response = try await request("v1/observations", connection: storedConnection, method: "POST", body: body)
            guard !Task.isCancelled, current == generation, repo.deviceId == source,
                  UserDefaults.standard.bool(forKey: Self.preference) else { return false }
            report = try JSONDecoder().decode(Report.self, from: response)
            guard report?.evaluation_policy.kind == "first_timely_upload" else {
                report = nil
                throw Failure.response
            }
            lastUpload = Date()
            return true
        } catch {
            if current == generation { failed = true }
            return false
        }
    }

    private static func digest(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func algorithmID() -> String {
        // Conservatively separate observations when local algorithm/profile preferences change.
        // Values stay on-device; only the digest crosses the explicit export boundary.
        let keys = ["profile.age", "profile.sex", "profile.weightKg", "profile.heightCm",
            "profile.hrMaxOverride", "profile.hrZoneThresholds", "hrv.window",
            "noop.hrvBaselineEpoch", "noop.recoveryBaselineEpoch", "dayCycle.mode"]
        let settings = keys.map { key in
            "\(key)=\(String(describing: UserDefaults.standard.object(forKey: key)))"
        }.joined(separator: "\n")
        return "noop-12.0.0@9f98f811/safw-recovery-v2/validation-v1/" + String(digest(settings).prefix(16))
    }
}

// Do not follow redirects with the receiver's bearer token, even to another HTTPS host.
private final class ValidationTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct PersonalValidationTask: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.scenePhase) private var phase
    @AppStorage(PersonalValidation.preference) private var enabled = false
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .task(id: "\(enabled)|\(phase == .active)|\(repo.deviceId)|\(repo.refreshSeq)") {
                PersonalValidationScheduler.updateSchedule()
                if enabled && phase == .active { _ = await PersonalValidation.shared.synchronize(repo: repo) }
            }
    }
}

struct PersonalValidationShortcut: View {
    var body: some View {
        NavigationLink { PersonalValidationView() } label: {
            NoopCard {
                HStack(spacing: NoopMetrics.cardInnerSpacing) {
                    Image(systemName: "checkmark.seal").foregroundStyle(StrandPalette.accent)
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        Text("Automatic comparison").font(StrandFont.headline)
                        Text("Sleep and recovery without copying daily numbers")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }.buttonStyle(.plain)
    }
}

struct PersonalValidationView: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var model = PersonalValidation.shared
    @AppStorage(PersonalValidation.preference) private var enabled = false
    @State private var origin = ""
    @State private var token = ""
    @State private var settingsFailed = false

    var body: some View {
        ScreenScaffold(title: "Automatic comparison", subtitle: "An optional reference check for your own data.") {
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                    Toggle("Enable automatic comparison", isOn: $enabled)
                    Text("When enabled, Safw sends up to 90 days of computed sleep totals, recovery, HRV and resting heart rate to the comparison service you configure. WHOOP reference results stay separate from Safw calculations.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    Text("The service needs a one-time setup and WHOOP authorization. Installing this app alone does not connect it.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    DisclosureGroup("Connection setup") {
                        VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
                            TextField("Comparison service URL", text: $origin)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            SecureField("Pairing token", text: $token)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("Save connection") {
                                do {
                                    try model.save(origin: origin, token: token)
                                    token = ""
                                    settingsFailed = false
                                    PersonalValidationScheduler.updateSchedule()
                                } catch { settingsFailed = true }
                            }
                            if settingsFailed {
                                Text("Check the HTTPS service URL and pairing token.").foregroundStyle(StrandPalette.metricAmber)
                            }
                        }
                    }
                    if enabled {
                        if model.configured {
                            Button("Connect WHOOP account") { Task { await model.connect() } }.disabled(model.busy)
                            Button("Sync comparison now") { Task { _ = await model.synchronize(repo: repo, force: true) } }
                                .disabled(model.busy)
                        } else { Text("The comparison service is not configured yet.") }
                        if model.busy { ProgressView() }
                        if model.failed {
                            Text("The comparison did not finish. Your saved strap data is still available for a later retry.")
                                .foregroundStyle(StrandPalette.metricAmber).font(StrandFont.footnote)
                        }
                        if let date = model.lastUpload {
                            Text("Last comparison upload").font(StrandFont.footnote)
                            Text(date, style: .relative).font(StrandFont.footnote)
                        }
                    }
                    Text("Background sync depends on iOS. Opening Safw also catches up automatically; continuous operation is not guaranteed.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
            if let report = model.report {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
                        Text(report.connected ? String(localized: "WHOOP connected") : String(localized: "WHOOP authorization needed"))
                            .font(StrandFont.headline)
                        if report.sync.error != nil {
                            Text("WHOOP reference sync needs attention. Older comparisons are not current results.")
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.metricAmber)
                        }
                        if report.groups.isEmpty { Text("Waiting for overlapping nights from both sources.") }
                        Text("The first upload within 24 hours of sleep is kept for comparison. Later recalculations do not replace it.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                        ForEach(report.groups) { group in
                            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                                Text("Matched nights: \(group.matched)").font(StrandFont.subhead)
                                Text("Unmatched or ambiguous: \(group.unmatched + group.ambiguous)").font(StrandFont.footnote)
                                Text("Quality exclusions: \(group.quality_excluded)").font(StrandFont.footnote)
                                metric("Recovery difference (points)", group.metrics["recovery"])
                                metric("Deep sleep difference (min)", group.metrics["deep"])
                                metric("REM difference (min)", group.metrics["rem"])
                                DisclosureGroup("Calculation version") {
                                    Text(verbatim: group.algorithm).font(StrandFont.footnote)
                                }
                            }
                        }
                        Text("These are differences from WHOOP, not clinical accuracy. The official API provides nightly stage totals, not an epoch-by-epoch sleep timeline.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }
        .onAppear {
            model.refreshConfiguration()
            origin = (try? model.connection().origin.absoluteString) ?? ""
        }
        .onChange(of: enabled) { _, active in
            if !active { model.suspend() }
            PersonalValidationScheduler.updateSchedule()
        }
    }

    @ViewBuilder private func metric(_ title: LocalizedStringKey, _ value: PersonalValidation.Metric?) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            HStack {
                Text(title)
                Spacer()
                if let value, value.n > 0, let mae = value.mae {
                    Text(mae.formatted(.number.precision(.fractionLength(1))))
                } else { Text("Not enough paired data") }
            }
            if let value, value.n > 0 { Text("Paired measurements: \(value.n)") }
        }.font(StrandFont.footnote)
    }
}
#endif
