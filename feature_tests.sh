#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

mkdir -p build

swiftc -swift-version 5 -parse-as-library \
    Sources/Models.swift \
    Sources/QuickLookController.swift \
    Tests/QuickLookTests.swift \
    -o build/QuickLookTests

swiftc -swift-version 5 -parse-as-library \
    Sources/GlobalHotKey.swift \
    Tests/HotKeyTests.swift \
    -o build/HotKeyTests

./build/HotKeyTests
./build/QuickLookTests
