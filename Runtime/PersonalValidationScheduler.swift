#if os(iOS) && MYNOOP_PERSONAL
import Foundation
import BackgroundTasks

// Best effort only. Foreground/data-refresh hooks catch up when iOS grants no background wake.
@MainActor enum PersonalValidationScheduler {
    static let identifier = (Bundle.main.bundleIdentifier ?? "app.m1.mynoop.noop") + ".validation"

    static func register(repo: Repository) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let completion = Completion(task)
            let worker = Task { @MainActor in
                updateSchedule()
                let success = await PersonalValidation.shared.synchronize(repo: repo, force: true)
                guard !Task.isCancelled else { return }
                completion.finish(success)
            }
            task.expirationHandler = {
                worker.cancel()
                completion.finish(false)
            }
        }
    }

    static func updateSchedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        guard UserDefaults.standard.bool(forKey: PersonalValidation.preference) else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private final class Completion: @unchecked Sendable {
        private let task: BGTask
        private let lock = NSLock()
        private var finished = false
        init(_ task: BGTask) { self.task = task }
        func finish(_ success: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            task.setTaskCompleted(success: success)
            task.expirationHandler = nil
        }
    }
}

#endif
