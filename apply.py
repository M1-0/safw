#!/usr/bin/env python3
"""Apply a narrow, fail-closed overlay to the pinned full upstream checkout."""
import argparse
import importlib.util
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG = json.loads((HERE / "config.json").read_text())
CATALOGS = ["Strand/Resources/Localizable.xcstrings",
            "Packages/StrandDesign/Sources/StrandDesign/Resources/Localizable.xcstrings",
            "NOOPWatch/Localizable.xcstrings", "NOOPWatchComplications/Localizable.xcstrings"]
LEGAL = ["LICENSE", "NOTICE", "ATTRIBUTION.md", "DISCLAIMER.md", "TERMS.md"]
DECODER = json.JSONDecoder()


def members(text, start=0):
    pos = text.index("{", start) + 1
    while True:
        while text[pos].isspace() or text[pos] == ",": pos += 1
        if text[pos] == "}": return
        key, end = DECODER.raw_decode(text, pos)
        pos = text.index(":", end) + 1
        while text[pos].isspace(): pos += 1
        value, end = DECODER.raw_decode(text, pos)
        yield key, pos, end, value
        pos = end


def catalog_edit(text, translations):
    start = next(s for k, s, _, _ in members(text) if k == "strings")
    edits = []
    for key, a, b, entry in members(text, start):
        if key not in translations or entry.get("shouldTranslate") is False: continue
        unit = {"stringUnit": {"state": "translated", "value": translations[key]}}
        segment = text[a:b]
        local = next((m for m in members(segment) if m[0] == "localizations"), None)
        if local:
            ar = next((m for m in members(segment, local[1]) if m[0] == "ar"), None)
            if ar:
                if ar[3] != unit: edits.append((a + ar[1], a + ar[2], json.dumps(unit, ensure_ascii=False)))
            else:
                pos = a + local[1] + 1
                edits.append((pos, pos, '\n        "ar" : ' + json.dumps(unit, ensure_ascii=False) + ("," if local[3] else "")))
        else:
            edits.append((a + 1, a + 1, '\n      "localizations" : {"ar": ' + json.dumps(unit, ensure_ascii=False) + '}' + ("," if entry else "")))
    for a, b, value in reversed(edits): text = text[:a] + value + text[b:]
    return text


def catalog_keys(text, keys):
    start = next(s for k, s, _, _ in members(text) if k == "strings")
    existing = {k for k, _, _, _ in members(text, start)}
    missing = sorted(set(keys) - existing)
    if not missing: return text
    entries = ',\n'.join('    ' + json.dumps(k, ensure_ascii=False) + ' : {}' for k in missing)
    return text[:start + 1] + '\n' + entries + (',' if existing else '') + text[start + 1:]


def replace(root, path, old, new, count=None):
    p = root / path
    text = p.read_text()
    actual = text.count(old)
    if actual == 0 or (count is not None and count != actual):
        raise ValueError(f"Upstream changed at {path}: expected {count}, found {actual}")
    p.write_text(text.replace(old, new))


def apply(root):
    import yaml
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    if sha != CONFIG["upstream_commit"]: raise ValueError("Review and rebase the overlay before changing upstream commit")
    if (root / "Personal/config.json").exists(): raise ValueError("Overlay already applied; use a clean worktree")
    personal = root / "Personal"
    personal.mkdir()
    shutil.copytree(HERE / "Runtime", personal / "Runtime")
    resource = personal / "Resources/ar.lproj"
    resource.mkdir(parents=True)
    shutil.copy2(HERE / "InfoPlist.strings", resource / "InfoPlist.strings")
    shutil.copy2(HERE / "config.json", personal / "config.json")
    replace(root, "Strand/App/AppLanguage.swift", '    case english = "en"', '    case arabic = "ar"\n    case english = "en"', 1)
    replace(root, "Strand/App/AppLanguage.swift", '        case .english:', '        case .arabic: return "العربية"\n        case .english:', 1)
    replace(root, "Strand/App/AppLanguage.swift", '    static func resolve(_ raw: String)', '''    static var isRightToLeft: Bool {
        activeLocale.language.characterDirection == .rightToLeft
    }

    // Physical gestures must agree with semantic navigation icons.
    static func navigationTranslation(_ horizontal: Double, rightToLeft: Bool) -> Double {
        rightToLeft ? -horizontal : horizontal
    }

    static func resolve(_ raw: String)''', 1)
    replace(root, "StrandiOS/App/StrandiOSApp.swift", '@main\n', '#if !MYNOOP_PERSONAL\n@main\n#endif\n', 1)
    replace(root, "StrandiOS/App/StrandiOSApp.swift", '.environment(\\.locale, AppLanguage.activeLocale)', '.environment(\\.locale, AppLanguage.activeLocale)\n                .environment(\\.layoutDirection, AppLanguage.isRightToLeft ? .rightToLeft : .leftToRight)', 1)
    for path in ["Strand/Liquid/LiquidTodayView.swift", "Strand/Screens/TodayView.swift"]:
        replace(root, path, 'daySwipeDelta(dx: dx)', 'daySwipeDelta(dx: CGFloat(AppLanguage.navigationTranslation(Double(dx), rightToLeft: AppLanguage.isRightToLeft)))', 1)
    replace(root, "StrandiOS/App/RootTabView.swift", 'selectedTab + (dx < 0 ? 1 : -1)', 'selectedTab + (AppLanguage.navigationTranslation(Double(dx), rightToLeft: AppLanguage.isRightToLeft) < 0 ? 1 : -1)', 1)
    for path in ["StrandiOS/App/RootTabView.swift", "Strand/Screens/TodayView.swift", "Strand/Liquid/LiquidTodayView.swift", "Packages/StrandDesign/Sources/StrandDesign/DayNavBar.swift"]:
        replace(root, path, 'systemName: "chevron.right"', 'systemName: "chevron.forward"')
    replace(root, "Packages/StrandDesign/Sources/StrandDesign/DayNavBar.swift", 'systemName: "chevron.left"', 'systemName: "chevron.backward"', 1)
    for value in ["1.0", "1.2", "1.6"]:
        replace(root, "Strand/Liquid/LiquidTodayView.swift", '.tracking(' + value + ')', '.tracking(AppLanguage.isRightToLeft ? 0 : ' + value + ')')
    replace(root, "Strand/Liquid/LiquidTodayView.swift", '            LiquidWordmark()', '            LiquidWordmark()\n                .environment(\\.layoutDirection, .leftToRight)', 1)
    replace(root, "Strand/Onboarding/OnboardingWizard.swift", 'systemName: "chevron.left"', 'systemName: "chevron.backward"', 1)
    replace(root, "Strand/Onboarding/OnboardingWizard.swift", 'return "arrow.right"', 'return "arrow.forward"', 1)
    replace(root, "Strand/Liquid/LiquidPrimitives.swift", '''            LiquidVessel(value: frac, tint: tint, animated: animated,
                         tapPassesThrough: tapPassesThrough)
                .frame(width: diameter, height: diameter)''', '''            #if MYNOOP_PERSONAL
            PersonalWaterVessel(value: frac, tint: tint, animated: animated,
                                tapPassesThrough: tapPassesThrough)
                .frame(width: diameter, height: diameter)
            #else
            LiquidVessel(value: frac, tint: tint, animated: animated,
                         tapPassesThrough: tapPassesThrough)
                .frame(width: diameter, height: diameter)
            #endif''', 1)
    replace(root, "Strand/Screens/StressView.swift", '''        return StatTile(
            label: label,
            value: value,
            caption: nil,
            accent: accent,
            delta: deltaText,
            deltaColor: deltaColor
        )''', '''        #if MYNOOP_PERSONAL
        return PersonalStressMarker(label: label, value: value, delta: deltaText,
                                    accent: accent, deltaColor: deltaColor)
        #else
        return StatTile(
            label: label,
            value: value,
            caption: nil,
            accent: accent,
            delta: deltaText,
            deltaColor: deltaColor
        )
        #endif''', 1)
    path = root / "Strand/Screens/StressView.swift"
    text = path.read_text()
    a = text.index("private struct StressHeroGauge: View {")
    b = text.index("// MARK: - Stress band", a)
    segment = text[a:b]
    segment = segment.replace('    var body: some View {\n', '    var body: some View {\n        #if MYNOOP_PERSONAL\n        PersonalStressGauge(score: score, tint: tint)\n        #else\n', 1)
    close = segment.rfind('    }\n}')
    segment = segment[:close] + '        #endif\n' + segment[close:]
    text = text[:a] + segment + text[b:]
    text = text.replace('.tracking(StrandFont.overlineTracking)', '.tracking(AppLanguage.isRightToLeft ? 0 : StrandFont.overlineTracking)')
    text = text.replace('return date.formatted(.dateTime.hour())', 'return date.formatted(.dateTime.hour().locale(AppLanguage.activeLocale))')
    # The Canvas uses chronological x positions; its clock ruler must keep the same order in RTL.
    ruler = '''                            Text(hourLabel(hi)).font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }'''
    if text.count(ruler) != 1: raise ValueError("Stress clock ruler changed upstream")
    text = text.replace(ruler, ruler + '\n                        .environment(\\.layoutDirection, .leftToRight)', 1)
    path.write_text(text)
    # Linux XML portability only; no decoding, schema, or physiological algorithm changes.
    replace(root, "Packages/StrandImport/Sources/StrandImport/XlsxSheet.swift", 'import Foundation\n', 'import Foundation\n#if canImport(FoundationXML)\nimport FoundationXML\n#endif\n', 1)
    import customize438
    customize438.apply(root, replace, catalog_keys)
    import customize_validation
    customize_validation.apply(root, replace, catalog_keys)
    import customize440
    customize440.apply(root, replace, catalog_keys)
    import customize441
    customize441.apply(root, replace, catalog_keys)
    translations = json.loads((HERE / "ar.json").read_text())
    translations.update(json.loads((HERE / "Audit/health-440-ar.json").read_text()))
    for name in CATALOGS:
        p = root / name
        source = p.read_text()
        if name == CATALOGS[0]: source = catalog_keys(source, ["All sources"])
        p.write_text(catalog_edit(source, translations))
    shutil.copy2(HERE / "Tests/PersonalFajrWakeTests.swift", root / "Packages/StrandAnalytics/Tests/StrandAnalyticsTests/PersonalFajrWakeTests.swift")
    legal = root / "build/personal/Legal"
    legal.mkdir(parents=True, exist_ok=True)
    for name in LEGAL: shutil.copy2(root / name, legal / name)
    project = yaml.safe_load((root / "project.yml").read_text())
    project["settings"]["base"].update({"BUNDLE_ID_PREFIX": CONFIG["bundle_prefix"], "CURRENT_PROJECT_VERSION": CONFIG["build"]})
    project["packages"]["SafwResearch"] = {"path": "Personal/Research"}
    app = project["targets"]["NOOPiOS"]
    app["dependencies"].append({"package": "SafwResearch"})
    app["settings"]["base"]["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "$(inherited) MYNOOP_PERSONAL"
    app["info"]["properties"].update({"CFBundleName": CONFIG["name"], "CFBundleDisplayName": CONFIG["name"]})
    customize_validation.configure_app(app)
    app["sources"] += ["Personal/Runtime", "Personal/Resources", {"path": "build/personal/Legal", "type": "folder", "buildPhase": "resources"}]
    widget = project["targets"]["NOOPiOSWidgets"]
    widget["sources"].append("Strand/Resources/Localizable.xcstrings")
    widget["info"]["properties"]["CFBundleDisplayName"] = CONFIG["name"]
    (root / "project.personal.generated.yml").write_text(yaml.safe_dump(project, sort_keys=False, allow_unicode=True))
    return inventory(root)


def inventory(root):
    spec = importlib.util.spec_from_file_location("upstream_i18n", root / "Tools/i18n_audit.py")
    audit = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = audit
    spec.loader.exec_module(audit)
    catalogs = []
    for name in CATALOGS:
        cat = json.loads((root / name).read_text())
        count = sum(v.get("shouldTranslate", True) for v in cat["strings"].values())
        pending = [k for k, v in cat["strings"].items() if v.get("shouldTranslate", True) and not audit._is_translated(v, "ar")]
        if audit.apple_format_gaps(cat, "ar"): raise ValueError(f"Placeholder mismatch: {name}")
        catalogs.append({"path": name, "entries": len(cat["strings"]), "translatable": count, "arabic": count - len(pending), "pending": pending})
    hardcoded, _ = audit.scan_ios()
    total = sum(c["translatable"] for c in catalogs)
    done = sum(c["arabic"] for c in catalogs)
    result = {"scope": "Static catalog coverage, not visual screen coverage", "total": total, "arabic": done,
              "percent": round(100 * done / total, 2), "uncatalogued_occurrences": len(hardcoded),
              "uncatalogued_unique": len({s for _, _, s in hardcoded}), "catalogs": catalogs, "uncatalogued": hardcoded}
    (root / "Personal/localization-audit.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    baseline = root / "Tools/i18n_extra_locale_baseline.txt"
    baseline.write_text(baseline.read_text() + '\n# Personal Arabic rollout: ratchet down as reviewed translations land.\n' + ''.join(f"{c['path']}:ar {c['translatable']-c['arabic']}\n" for c in catalogs))
    return {k: v for k, v in result.items() if k not in {"catalogs", "uncatalogued"}}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("checkout", type=Path)
    args = parser.parse_args()
    print(json.dumps(apply(args.checkout.resolve()), ensure_ascii=False))
