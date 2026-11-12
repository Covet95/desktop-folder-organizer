import Combine
import Foundation

final class AppStore: ObservableObject {
    @Published private(set) var panels: [PanelStore] = []
    @Published private(set) var fileOperations: [FileOperationRecord] = []
    @Published private(set) var autoAbsorbStatus = AutoAbsorbStatus()
    @Published private(set) var persistenceWarning: String?

    // Keep the established result type available to existing UI call sites.
    typealias AbsorbResult = FileOperationService.AbsorbResult
    typealias AbsorbSourceDisposition = FileOperationService.AbsorbSourceDisposition

    var onShowFileActivity: (() -> Void)?
    var onFileRestored: ((URL) -> Void)?
    var onManagedItemsChanged: (([URL]) -> Void)?

    private let persistence: PanelStateRepository
    private let fileOperationService: FileOperationService
    private let configuredStorageDirectory: URL?
    private var saveWork: DispatchWorkItem?
    private var panelSubscriptions: [UUID: AnyCancellable] = [:]

    init(
        persistence: PanelStateRepository = JSONPanelStateRepository(),
        storageDirectory: URL? = nil
    ) {
        self.persistence = persistence
        self.configuredStorageDirectory = storageDirectory

        let service = FileOperationService(directory: persistence.supportDirectory)
        self.fileOperationService = service
        self.fileOperations = service.initialOperations
        if let warning = service.loadWarning {
            self.autoAbsorbStatus = AutoAbsorbStatus(
                phase: .attention,
                pendingCount: 1,
                message: warning
            )
        }

        switch persistence.load() {
        case .loaded(let saved) where !saved.isEmpty:
            panels = saved.map(PanelStore.init)
        case .recoveryRequired(let warning):
            persistenceWarning = warning
            panels = [PanelStore(config: .makeDefault(index: 0))]
        case .missing, .loaded:
            panels = [PanelStore(config: .makeDefault(index: 0))]
        }
        panels.forEach(observe)

        service.onOperationsChanged = { [weak self] operations in
            self?.fileOperations = operations
        }
        service.onRecoveryAttention = { [weak self] message in
            self?.updateAutoAbsorbStatus(phase: .attention, pendingCount: 1, message: message)
        }
    }

    var storageDirectory: URL {
        configuredStorageDirectory ?? FileOperationService.defaultStorageDirectory
    }

    var canDeletePanel: Bool { panels.count > 1 }

    var allHidden: Bool {
        !panels.isEmpty && panels.allSatisfy { $0.config.isHidden }
    }

    var recoverableOperationCount: Int {
        fileOperations.filter(\.canRestore).count
    }

    func newPanel() {
        let panel = PanelStore(config: .makeDefault(index: panels.count))
        observe(panel)
        panels.append(panel)
        scheduleSave()
    }

    func removePanel(_ panel: PanelStore) {
        guard canDeletePanel, let index = panels.firstIndex(where: { $0.id == panel.id }) else { return }
        panelSubscriptions[panel.id] = nil
        panels.remove(at: index)
        scheduleSave()
    }

    func toggleAll() {
        let hidden = !allHidden
        for panel in panels {
            panel.config.isHidden = hidden
        }
    }

    func absorb(
        urls: [URL],
        kind: FileOperationKind = .manualAbsorb,
        completion: @escaping (AbsorbResult) -> Void
    ) {
        fileOperationService.absorb(
            urls: urls,
            storageURL: storageDirectory,
            kind: kind,
            completion: completion
        )
    }

    func renameItem(
        at source: URL,
        to newName: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        fileOperationService.renameItem(at: source, to: newName) { [weak self] result in
            if case .success(let destination) = result {
                self?.replacePanelReferences(from: source, to: destination)
                self?.saveNow()
            }
            completion(result)
        }
    }

    func restoreOperation(
        _ id: UUID,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        fileOperationService.restoreOperation(id) { [weak self] result in
            switch result {
            case .success(let outcome):
                self?.replacePanelReferences(from: outcome.movedURL, to: outcome.restoredURL)
                self?.saveNow()
                self?.onFileRestored?(outcome.restoredURL)
                completion(.success(outcome.restoredURL))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func restoreLatestOperation(
        for path: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let record = fileOperations
            .filter({ $0.canRestore && $0.destinationPath == URL(fileURLWithPath: path).standardizedFileURL.path })
            .max(by: { $0.createdAt < $1.createdAt })
        else {
            completion(.failure(FileOperationJournalError.operationNotRestorable))
            return
        }
        restoreOperation(record.id, completion: completion)
    }

    private func replacePanelReferences(from source: URL, to destination: URL) {
        let sourcePath = source.standardizedFileURL.path
        let destinationPath = destination.standardizedFileURL.path
        for panel in panels {
            panel.replacePath(from: sourcePath, to: destinationPath)
        }
    }

    func updateAutoAbsorbStatus(
        phase: AutoAbsorbPhase,
        pendingCount: Int = 0,
        message: String
    ) {
        autoAbsorbStatus = AutoAbsorbStatus(
            phase: phase,
            pendingCount: pendingCount,
            message: message,
            updatedAt: Date()
        )
    }

    // Preserve the AppStore facade used by application shutdown coordination.
    func drainFileOperations(completion: @escaping () -> Void) {
        fileOperationService.drain(completion: completion)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil

        do {
            try persistence.save(panels.map(\.config))
            persistenceWarning = nil
        } catch {
            persistenceWarning = error.localizedDescription
            NSLog("DesktopFolderWidget: panel state save failed: \(error)")
        }
    }

    private func observe(_ panel: PanelStore) {
        panelSubscriptions[panel.id] = panel.$config
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleSave() }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
}
