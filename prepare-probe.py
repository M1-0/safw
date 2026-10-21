#!/usr/bin/env python3
import json
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
root = Path(sys.argv[1]).resolve()
dest = root / "build/personal-import-probe"
sources = dest / "Sources/ImportProbe"
sources.mkdir(parents=True, exist_ok=True)
deps = ',\n'.join(f'.package(path: {json.dumps(str(root / "Packages" / p))})' for p in ["StrandImport", "WhoopStore"])
(dest / "Package.swift").write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ImportProbe", platforms: [.macOS(.v13)],
    dependencies: [''' + deps + '''],
    targets: [.executableTarget(name: "ImportProbe", dependencies: [
        .product(name: "StrandImport", package: "StrandImport"),
        .product(name: "WhoopStore", package: "WhoopStore")])])
''')
shutil.copy2(root / "Strand/Data/WhoopImporter.swift", sources / "WhoopImporter.swift")
shutil.copy2(HERE / "Tests/ImportProbe.swift", sources / "ImportProbe.swift")
