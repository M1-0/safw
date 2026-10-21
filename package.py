#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG = json.loads((HERE / "config.json").read_text())
LEGAL = ["LICENSE", "NOTICE", "ATTRIBUTION.md", "DISCLAIMER.md", "TERMS.md"]


def prepare(root, app):
    dependencies = root / "build/personal-device/SourcePackages/checkouts"
    for required in ["GRDB.swift", "ZIPFoundation", "swift-markdown-ui"]:
        if not (dependencies / required).is_dir(): raise ValueError(f"Missing license source: {required}")
    for package in dependencies.iterdir():
        notices = [p for p in package.iterdir() if p.is_file() and p.name.lower().startswith(("license", "notice", "copying"))]
        if not notices: raise ValueError(f"No root license/notice for {package.name}")
        dest = app / "Legal/ThirdParty" / package.name
        dest.mkdir(parents=True, exist_ok=True)
        for notice in notices: shutil.copy2(notice, dest / notice.name)


def validate(root, app):
    info = plistlib.loads((app / "Info.plist").read_bytes())
    widget = plistlib.loads((app / "PlugIns/NOOPWidgets.appex/Info.plist").read_bytes())
    expected = CONFIG["bundle_prefix"] + ".noop"
    assert info["CFBundleIdentifier"] == expected
    assert info["CFBundleDisplayName"] == CONFIG["name"]
    assert widget["CFBundleIdentifier"] == expected + ".widgets"
    assert widget["CFBundleDisplayName"] == CONFIG["name"]
    assert info["CFBundleVersion"] == widget["CFBundleVersion"] == CONFIG["build"]
    assert info["AppGroupIdentifier"] == widget["AppGroupIdentifier"]
    assert info["AppGroupIdentifier"].startswith("group." + CONFIG["bundle_prefix"] + ".")
    for name in LEGAL: assert (app / "Legal" / name).read_bytes() == (root / name).read_bytes(), name
    assert (app / "Legal/ThirdParty/GRDB.swift").is_dir()
    assert (app / "ar.lproj/Localizable.strings").is_file(), "Arabic catalog not compiled"
    assert (app / "ar.lproj/InfoPlist.strings").is_file(), "Arabic permission descriptions missing"
    return info


def package(root, app):
    info = validate(root, app)
    dest = root / "build/personal-dist"
    dest.mkdir(parents=True, exist_ok=True)
    ipa = dest / f'{CONFIG["artifact_name"]}-{info["CFBundleShortVersionString"]}-{info["CFBundleVersion"]}-unsigned.ipa'
    with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED) as output:
        for path in app.rglob("*"):
            if path.is_file(): output.write(path, Path("Payload") / app.name / path.relative_to(app))
    manifest = {"ipa": ipa.name, "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
                "bundle_id": info["CFBundleIdentifier"], "sha256": hashlib.sha256(ipa.read_bytes()).hexdigest(),
                "customization_commit": os.environ.get("GITHUB_SHA") or subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=HERE, text=True).strip(),
                "upstream_commit": CONFIG["upstream_commit"], "hardware_tested": False,
                "signing": "Ad-hoc entitlement template; SideStore signs for the user's device"}
    (dest / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(ipa)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkout", required=True, type=Path)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--prepare", type=Path)
    group.add_argument("--package", type=Path)
    args = parser.parse_args()
    root = args.checkout.resolve()
    prepare(root, args.prepare.resolve()) if args.prepare else package(root, args.package.resolve())
