import AppKit

final class PanelDropController {
    private let store: PanelStore
    private let gridView: GridView
    private let fileActions: PanelFileActionCoordinator
    private let isSearching: () -> Bool
    private let setHighlight: (Bool) -> Void

    init(
        store: PanelStore,
        gridView: GridView,
        fileActions: PanelFileActionCoordinator,
        isSearching: @escaping () -> Bool,
        setHighlight: @escaping (Bool) -> Void
    ) {
        self.store = store
        self.gridView = gridView
        self.fileActions = fileActions
        self.isSearching = isSearching
        self.setHighlight = setHighlight
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.types?.contains(PanelView.itemPasteboardType) == true {
            guard !isSearching() else { return [] }
            setHighlight(true)
            return .move
        }

        guard sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) else { return [] }

        setHighlight(true)
        return .move
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.types?.contains(PanelView.itemPasteboardType) == true {
            guard !isSearching() else { return [] }
            let point = gridView.convert(sender.draggingLocation, from: nil)
            let index = gridView.index(at: point, itemCount: store.filteredItems.count)
            gridView.setDropTarget(index)
            return .move
        }

        return sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ? .move : []
    }

    func draggingExited() {
        clearDropState()
    }

    func performDrop(
        pasteboard: NSPasteboard,
        location: NSPoint,
        completion: ((AppStore.AbsorbResult) -> Void)? = nil
    ) -> Bool {
        defer { clearDropState() }

        if pasteboard.types?.contains(PanelView.itemPasteboardType) == true {
            guard !isSearching(),
                  let idString = pasteboard.string(forType: PanelView.itemPasteboardType),
                  let id = UUID(uuidString: idString)
            else { return false }

            let point = gridView.convert(location, from: nil)
            let index = gridView.index(at: point, itemCount: store.filteredItems.count)
            store.move(id: id, toIndex: index)
            return true
        }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options)
        let urls = (objects as? [URL]) ?? ((objects as? [NSURL])?.map { $0 as URL } ?? [])
        guard !urls.isEmpty else { return false }
        fileActions.absorb(urls, completion: completion)
        return true
    }

    func clearDropState() {
        gridView.setDropTarget(nil)
        setHighlight(false)
    }
}
