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
echo "=== COPY PATH CONTEXT MENU TESTS ==="
swiftc -swift-version 5 -parse-as-library \
    Sources/Models.swift \
    Sources/PanelAppearance.swift \
    Sources/PanelStateRepository.swift \
    Sources/FileOperationJournal.swift \
    Sources/FileOperationService.swift \
    Sources/AutoAbsorbStatus.swift \
    Sources/PanelStore.swift \
    Sources/AppStore.swift \
    Sources/DesktopWatcher.swift \
    Sources/DesktopIntakeCoordinator.swift \
    Sources/IconProvider.swift \
    Sources/ItemView.swift \
    Sources/AddTileView.swift \
    Sources/GridView.swift \
    Sources/QuickLookController.swift \
    Sources/PanelView.swift \
    Sources/PanelToolbarView.swift \
    Sources/PanelSectionHeaderView.swift \
    Sources/PanelEmptyStateView.swift \
    Sources/PanelFileActionCoordinator.swift \
    Sources/PanelContextMenuController.swift \
    Sources/PanelDropController.swift \
    Sources/SettingsViewController.swift \
    Tests/CopyPathTests.swift \
    -o build/CopyPathTests
./build/CopyPathTests
