"""Optional personal validation export; no upstream algorithm, BLE or database-schema changes."""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def apply(root, replace, catalog_keys):
    replace(root, 'StrandiOS/App/RootTabView.swift',
            '        .background(PersonalMinuteRecordingTask())',
            '        .background(PersonalMinuteRecordingTask())\n        .background(PersonalValidationTask())', 1)
    replace(root, 'Strand/Liquid/LiquidTodayView.swift',
            'if selectedDayOffset == 0 { PersonalStressShortcut() }',
            'if selectedDayOffset == 0 {\n                        PersonalStressShortcut()\n                        PersonalValidationShortcut()\n                    }', 1)
    replace(root, 'Strand/Screens/DataSourcesView.swift',
            '                whoopCard.staggeredAppear(index: 0)',
            '                #if os(iOS) && MYNOOP_PERSONAL\n                PersonalValidationShortcut()\n                #endif\n                whoopCard.staggeredAppear(index: 0)', 1)
    replace(root, 'Strand/Screens/DataSourcesView.swift',
            'subtitle: "Everything stays on \\(Platform.deviceNounPhrase). Bring your history in once, then it\'s yours.",',
            'subtitle: "Your strap data is computed locally. Optional connections and exports require your permission.",', 1)
    replace(root, 'StrandiOS/App/StrandiOSApp.swift',
            '        _model = StateObject(wrappedValue: model)',
            '        _model = StateObject(wrappedValue: model)\n        #if MYNOOP_PERSONAL\n        PersonalValidationScheduler.register(repo: model.repo)\n        #endif', 1)
    main = root / 'Strand/Resources/Localizable.xcstrings'
    extras = json.loads((HERE / 'Audit/extra-validation-ar.json').read_text())
    main.write_text(catalog_keys(main.read_text(), extras.keys()))


def configure_app(app):
    properties = app['info']['properties']
    properties.setdefault('BGTaskSchedulerPermittedIdentifiers', []).append('$(PRODUCT_BUNDLE_IDENTIFIER).validation')
    properties.setdefault('CFBundleURLTypes', []).append({'CFBundleURLSchemes': ['safw-validation']})
