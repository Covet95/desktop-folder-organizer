#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

mkdir -p build
swiftc -swift-version 5 -parse-as-library \
    Sources/Models.swift \
    Sources/ColorHex.swift \
    Sources/Persistence.swift \
    Sources/FileOperationJournal.swift \
    Sources/AutoAbsorbStatus.swift \
    Sources/PanelStore.swift \
    Sources/AppStore.swift \
    Sources/IconProvider.swift \
    Sources/ItemView.swift \
    Sources/AddTileView.swift \
    Sources/GridView.swift \
    Sources/QuickLookController.swift \
    Sources/PanelView.swift \
    Sources/PanelToolbarView.swift \
    Sources/PanelEmptyStateView.swift \
    Sources/PanelFileActionCoordinator.swift \
    Sources/PanelContextMenuController.swift \
    Sources/PanelDropController.swift \
    Sources/SettingsViewController.swift \
    Tests/SnapshotTests.swift \
    -o build/SnapshotTests

./build/SnapshotTests
