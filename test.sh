#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

mkdir -p build
swiftc -swift-version 5 -parse-as-library \
    Sources/Models.swift \
    Sources/Persistence.swift \
    Sources/FileOperationJournal.swift \
    Sources/AutoAbsorbStatus.swift \
    Sources/PanelStore.swift \
    Sources/AppStore.swift \
    Sources/DesktopWatcher.swift \
    Sources/DesktopIntakeCoordinator.swift \
    Tests/StoreTests.swift \
    -o build/StoreTests

./build/StoreTests
