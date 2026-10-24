"""Capture actual SwiftUI screens; synthetic fixtures are confined to this disposable simulator."""
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
OUT = ROOT / 'build/personal-screenshots'
OUT.mkdir(parents=True, exist_ok=True)
APP = ROOT / 'build/personal-simulator/Build/Products/Debug-iphonesimulator/NOOP Staging.app'
BUNDLE = 'app.m1.mynoop.noop'


def sim(*args, timeout=300):
    result = subprocess.run(['xcrun', 'simctl', *args], text=True, timeout=timeout, capture_output=True)
    with (OUT / 'simctl.log').open('a') as output:
        output.write(json.dumps(args) + '\n' + result.stdout + result.stderr + '\n')
    result.check_returncode()
    return result.stdout.strip()


runtimes = json.loads(sim('list', 'runtimes', '--json'))['runtimes']
choices = [r for r in runtimes if r.get('isAvailable') and '.iOS-' in r['identifier']]
assert choices, 'No installed iOS simulator runtime'
runtime = max(choices, key=lambda r: tuple(int(n) for n in r['version'].split('.')))
device = sim('create', 'Safw iPhone 13 audit', 'com.apple.CoreSimulator.SimDeviceType.iPhone-13', runtime['identifier'])
report = {'device': 'iPhone 13 simulator', 'runtime': runtime['version'], 'bundle': BUNDLE,
          'customization_source_commit': os.environ.get('GITHUB_SHA'),
          'build': plistlib.loads((APP / 'Info.plist').read_bytes())['CFBundleVersion'],
          'display_name': plistlib.loads((APP / 'Info.plist').read_bytes())['CFBundleDisplayName'],
          'hardware_tested': False, 'screens': []}


def capture(name, *launch_args, synthetic=False):
    result = sim('launch', '--terminate-running-process', device, BUNDLE, *launch_args)
    pid = re.search(r': (\d+)\s*$', result)
    assert pid, f'Launch did not return a PID: {result}'
    time.sleep(8)
    processes = sim('spawn', device, 'launchctl', 'list')
    assert any(row.split() and row.split()[0] == pid[1] for row in processes.splitlines()), f'{name}: app exited after launch'
    sim('io', device, 'screenshot', str(OUT / (name + '.png')))
    report['screens'].append({'name': name, 'synthetic_data': synthetic, 'survived_launch_seconds': 8})
    print('CAPTURED', name, flush=True)


try:
    sim('boot', device)
    sim('bootstatus', device, '-b', timeout=600)
    sim('ui', device, 'appearance', 'dark')
    sim('status_bar', device, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100')
    assert report['display_name'] == 'صفو', 'Personal app name regressed'
    sim('install', device, str(APP))
    # Record registration separately from launching, to distinguish simulator installation failures.
    (OUT / 'installed-apps.json').write_text(sim('listapps', device))
    capture('01-first-launch')
    container = Path(sim('get_app_container', device, BUNDLE, 'data'))
    prefs = plistlib.loads((container / 'Library/Preferences' / (BUNDLE + '.plist')).read_bytes())
    assert prefs.get('noop.appLanguage') == 'ar'
    assert prefs.get('AppleLanguages') == ['ar']
    report['arabic_defaults_persisted'] = True
    capture('02-today-empty', '--demo-screen', 'liquidtoday')
    capture('empty-stress', '--demo-screen', 'stress')
    capture('empty-stress-research', '--demo-screen', 'stress', '-personal.stressMinuteResearch', 'YES')
    capture('03-tabs-seeded', '--demo-seed', synthetic=True)
    for index, screen in enumerate(['liquidtoday', 'stress', 'sleep', 'trends', 'workouts', 'health',
                                    'live', 'insights', 'explore', 'compare', 'settings', 'devices', 'datasources'], 4):
        capture(f'{index:02d}-{screen}', '--demo-seed', '--demo-screen', screen, synthetic=True)
    capture('17-onboarding', '--demo-screen', 'onboarding')
    capture('18-water-states', '--demo-screen', 'waterstates', synthetic=True)
    capture('19-quiet-liquidtoday', '--demo-seed', '--demo-screen', 'liquidtoday', '-noop.quietMotion', 'YES', synthetic=True)
    for screen in ['breathe', 'scoringguide', 'scoringcharge', 'scoringeffort', 'scoringrest',
                   'deeptimeline', 'customizetoday', 'customizemetrics', 'customizecards',
                   'applehealth', 'storage', 'backup', 'hydration', 'hrvsnapshot', 'validation', 'healthinsights', 'glucose']:
        capture('flow-' + screen, '--demo-seed', '--demo-screen', screen, synthetic=True)
    sim('ui', device, 'content_size', 'extra-extra-extra-large')
    for screen in ['liquidtoday', 'stress', 'datasources', 'breathe', 'customizetoday', 'scoringcharge', 'validation', 'healthinsights', 'glucose']:
        capture('large-' + screen, '--demo-seed', '--demo-screen', screen, synthetic=True)
    capture('large-first-launch')
finally:
    (OUT / 'smoke-report.json').write_text(json.dumps(report, indent=2) + '\n')
    try:
        logs = sim('spawn', device, 'log', 'show', '--last', '5m', '--style', 'compact',
                   '--predicate', 'process == "SpringBoard" OR process == "runningboardd" OR process CONTAINS "NOOP"')
        (OUT / 'launch-diagnostics.log').write_text(logs)
    except (subprocess.SubprocessError, OSError) as error:
        print('Could not collect simulator system log:', error, flush=True)
    crash_folder = Path.home() / 'Library/Logs/DiagnosticReports'
    for crash in crash_folder.glob('*NOOP*'):
        if crash.is_file(): shutil.copy2(crash, OUT / crash.name)
    subprocess.run(['xcrun', 'simctl', 'shutdown', device], check=False)
