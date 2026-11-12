#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

mkdir -p build
swiftc -swift-version 5 -parse-as-library \
    Sources/Models.swift \
    Sources/PanelStateRepository.swift \
    Sources/FileOperationJournal.swift \
    Sources/FileOperationService.swift \
    Sources/AutoAbsorbStatus.swift \
    Sources/PanelStore.swift \
    Sources/AppStore.swift \
    Sources/DesktopWatcher.swift \
    Sources/DesktopIntakeCoordinator.swift \
    Tests/StoreTests.swift \
    -o build/StoreTests

./build/StoreTests

echo
echo "=== PANEL STATE REPOSITORY TESTS ==="
swiftc -swift-version 5 -parse-as-library \
    Sources/Models.swift \
    Sources/PanelStateRepository.swift \
    Tests/PanelStateRepositoryTests.swift \
    -o build/PanelStateRepositoryTests
./build/PanelStateRepositoryTests

echo
echo "=== FILE OPERATION SERVICE TESTS ==="
swiftc -swift-version 5 -parse-as-library \
    Sources/FileOperationJournal.swift \
    Sources/FileOperationService.swift \
    Tests/FileOperationServiceTests.swift \
    -o build/FileOperationServiceTests
./build/FileOperationServiceTests


echo
echo "=== WIDGET SUMMARY DATA TESTS ==="
swiftc -swift-version 5 -parse-as-library \
    Shared/WidgetSnapshot.swift \
    Tests/WidgetSnapshotTests.swift \
    -o build/WidgetSnapshotTests
./build/WidgetSnapshotTests
