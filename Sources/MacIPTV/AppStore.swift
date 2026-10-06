import Foundation
import Observation
import MacIPTVCore

@Observable
@MainActor
final class AppStore {
    var channels: [Channel] = []
    var guide: XMLTVGuide?
    var guideWarning: String?
    var lastError: String?
    var isImporting = false
    var sourceSummary: String?
    var demoMode = false
    var networkPolicy = NetworkPolicy()
    private var pendingHTTPSource: SavedSource?
    private var activeSource: SavedSource?
    private(set) var activeSourceID: UUID?
    var needsHTTPConsent: Bool { pendingHTTPSource != nil }
    func authorizeHTTPForPendingSource() {
        guard var saved = pendingHTTPSource else { return }
        saved.policy.allowHTTP = true
        load(saved.source, policy: saved.policy, fileBookmark: saved.fileBookmark)
    }
    func requestHTTPConsentForPlayback(sourceID: UUID?) {
        guard sourceID != nil, sourceID == activeSourceID,
              let saved = activeSource, !saved.policy.allowHTTP, pendingHTTPSource == nil else { return }
        pendingHTTPSource = saved
        lastError = IPTVError.httpConsentRequired.errorDescription
    }
    var selectedChannelID: String? {
        didSet {
            guard let id = selectedChannelID, id != oldValue else { return }
            previousChannelID = oldValue
            recentIDs.removeAll { $0 == id }
            recentIDs.insert(id, at: 0)
            recentIDs = Array(recentIDs.prefix(20))
            persistNavigation()
        }
    }
    var previousChannelID: String?
    var recentIDs: [String] = []
    var favoriteOrder: [String] = []
    var searchText = "" { didSet { recentNavigationIDs = nil } }
    /// Centinela visible: una fila con tag nil no puede seleccionarse en List.
    var selectedGroup: String? = "__todos" { didSet { recentNavigationIDs = nil } }
    private var recentNavigationIDs: [String]?
    var favorites: Set<String> = []
    var showGuide = false
    var showSettings = false

    private let keychain = KeychainSourceRepository()
    private let importer = SourceImporter()
    private let defaultsKey = "favorites.ids"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restoreFavorites()
    }

    /// Generacion de importacion: un resultado tardio nunca pisa una fuente
    /// mas nueva, una eliminacion ni el modo demo.
    private var importGeneration = 0
    private var importTask: Task<Void, Never>?

    var hasChannels: Bool { !channels.isEmpty }

    func bootstrap(demo: Bool) {
        restoreFavorites()
        if demo {
            // Cambiar a demo invalida cualquier importacion en curso: un
            // resultado tardio no puede pisar el contenido de demostracion.
            importTask?.cancel()
            importGeneration += 1
            isImporting = false
            lastError = nil
            demoMode = true
            networkPolicy = NetworkPolicy()
            activeSource = nil
            activeSourceID = nil
            applyDemo()
            return
        }
        refresh()
    }

    // MARK: Favoritos (UserDefaults: no contienen credenciales)

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        if favorites.contains(id) { favoriteOrder.append(id) }
        else { favoriteOrder.removeAll { $0 == id } }
        persistNavigation()
        // En demo los favoritos son solo de esta sesion.
        if !demoMode {
            defaults.set(Array(favorites), forKey: defaultsKey)
        }
    }

    private func persistNavigation() {
        guard !demoMode else { return }
        defaults.set(favoriteOrder, forKey: "favorites.order")
        defaults.set(recentIDs, forKey: "channels.recent")
    }

    func moveFavorite(_ id: String, by delta: Int) {
        guard let index = favoriteOrder.firstIndex(of: id) else { return }
        let target = index + delta
        guard favoriteOrder.indices.contains(target) else { return }
        favoriteOrder.swapAt(index, target)
        persistNavigation()
    }

    func returnToPreviousChannel() {
        guard let id = previousChannelID, channels.contains(where: { $0.id == id }) else { return }
        selectedChannelID = id
    }

    private func restoreFavorites() {
        recentIDs = Array((defaults.stringArray(forKey: "channels.recent") ?? []).prefix(20))
        if let ids = defaults.stringArray(forKey: defaultsKey) {
            favorites = Set(ids)
            favoriteOrder = defaults.stringArray(forKey: "favorites.order") ?? ids
            favoriteOrder = favoriteOrder.filter { favorites.contains($0) }
            favoriteOrder.append(contentsOf: ids.filter { !favoriteOrder.contains($0) })
        }
    }

    // MARK: Importacion

    /// Reemplaza la fuente solo si la importacion tiene exito; cualquier
    /// fallo deja intactos los canales y la configuracion anteriores.
    func load(_ source: SourceConfiguration, policy: NetworkPolicy = NetworkPolicy(), fileBookmark: Data? = nil) {
        let saved = SavedSource(source: source, policy: policy, fileBookmark: fileBookmark)
        pendingHTTPSource = nil
        importTask?.cancel()
        importGeneration += 1
        let generation = importGeneration
        isImporting = true
        lastError = nil
        importTask = Task { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await self.importer.importSource(source, policy: policy, fileBookmark: fileBookmark)
                // Verifica que sigue siendo la importacion vigente.
                guard !Task.isCancelled, generation == self.importGeneration else { return }
                // Primero persiste la configuracion; si el Llavero falla,
                // conserva canales y fuente previos.
                try await self.keychain.save(saved)
                guard !Task.isCancelled, generation == self.importGeneration else { return }
                // Cargar una fuente real desde demo sale del modo demo.
                if self.demoMode {
                    self.demoMode = false
                    self.restoreFavorites()
                }
                self.selectedGroup = "__todos"
                self.apply(outcome)
                self.sourceSummary = source.summary
                self.networkPolicy = policy
                self.activeSource = saved
                self.activeSourceID = UUID()
            } catch IPTVError.httpConsentRequired {
                if generation == self.importGeneration {
                    self.pendingHTTPSource = saved
                    self.lastError = IPTVError.httpConsentRequired.errorDescription
                }
            } catch is CancellationError {
                // Cancelada por una importacion mas nueva o por limpiar la fuente.
            } catch let error as IPTVError {
                if generation == self.importGeneration {
                    self.lastError = error.errorDescription
                }
            } catch {
                if generation == self.importGeneration {
                    self.lastError = "No se pudo cargar la fuente."
                }
            }
            if generation == self.importGeneration {
                self.isImporting = false
            }
        }
    }

    func refresh(allowAuthentication: Bool = false) {
        importTask?.cancel()
        importGeneration += 1
        let generation = importGeneration
        isImporting = true
        lastError = nil
        importTask = Task { [weak self] in
            guard let self else { return }
            do {
                let source = try await self.keychain.loadSaved(allowAuthentication: allowAuthentication)
                guard !Task.isCancelled, generation == self.importGeneration else { return }
                self.isImporting = false
                if let source { self.load(source.source, policy: source.policy, fileBookmark: source.fileBookmark) }
            } catch {
                guard !Task.isCancelled, generation == self.importGeneration else { return }
                self.lastError = (error as? LocalizedError)?.errorDescription ?? "No se pudo leer la fuente guardada."
                self.isImporting = false
            }
        }
    }

    private func apply(_ outcome: ImportOutcome) {
        recentNavigationIDs = nil
        channels = outcome.channels
        guide = outcome.guide
        guideWarning = outcome.guideWarning
        let live = Set(outcome.channels.map(\.id))
        favorites.formIntersection(live)
        favoriteOrder.removeAll { !live.contains($0) }
        recentIDs.removeAll { !live.contains($0) }
        if let previous = previousChannelID, !live.contains(previous) { previousChannelID = nil }
        persistNavigation()
        if !demoMode {
            defaults.set(Array(favorites), forKey: defaultsKey)
        }
        if let selected = selectedChannelID, !live.contains(selected) {
            selectedChannelID = nil
        }
    }

    func removeSource() {
        activeSource = nil
        activeSourceID = nil
        pendingHTTPSource = nil
        importTask?.cancel()
        importGeneration += 1
        let generation = importGeneration
        lastError = nil
        isImporting = true
        importTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.keychain.clear()
                guard !Task.isCancelled, generation == self.importGeneration else { return }
                self.channels = []
                self.guide = nil
                self.guideWarning = nil
                self.sourceSummary = nil
                self.selectedChannelID = nil
                self.demoMode = false
                self.favorites = []
                self.favoriteOrder = []
                self.recentIDs = []
                self.previousChannelID = nil
                self.persistNavigation()
                self.selectedGroup = "__todos"
                defaults.removeObject(forKey: self.defaultsKey)
            } catch {
                guard !Task.isCancelled, generation == self.importGeneration else { return }
                self.lastError = (error as? LocalizedError)?.errorDescription ?? "No se pudo quitar la fuente."
            }
            if generation == self.importGeneration { self.isImporting = false }
        }
    }

    func startDemo() {
        activeSource = nil
        activeSourceID = nil
        pendingHTTPSource = nil
        networkPolicy = NetworkPolicy()
        importTask?.cancel()
        importGeneration += 1
        isImporting = false
        lastError = nil
        demoMode = true
        applyDemo()
    }

    /// Sube o baja la seleccion dentro de la lista visible (teclado).
    func moveSelection(by delta: Int) {
        var list = visibleChannels
        if selectedGroup == "__recientes" {
            if recentNavigationIDs == nil { recentNavigationIDs = list.map(\.id) }
            let lookup = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            list = (recentNavigationIDs ?? []).compactMap { lookup[$0] }
        }
        guard !list.isEmpty else { return }
        if let idx = list.firstIndex(where: { $0.id == selectedChannelID }) {
            selectedChannelID = list[min(max(idx + delta, 0), list.count - 1)].id
        } else {
            selectedChannelID = list.first?.id
        }
    }

    // MARK: Demostracion (no toca la suscripcion guardada ni sus favoritos)

    private func applyDemo() {
        let parsed = M3UParser.parse(DemoContent.playlistText, baseURL: nil)
        channels = parsed.channels
        guide = DemoContent.makeGuide()
        sourceSummary = "Modo demostracion"
        favorites = []
        favoriteOrder = []
        recentIDs = []
        previousChannelID = nil
        selectedChannelID = nil
        selectedGroup = "__todos"
    }

    // MARK: Listas derivadas

    var groups: [String] {
        var seen = Set<String>()
        return channels.map(\.group).filter { seen.insert($0).inserted }.sorted()
    }

    var visibleChannels: [Channel] {
        var list: [Channel]
        if selectedGroup == "__favoritos" {
            let lookup = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            list = favoriteOrder.compactMap { lookup[$0] }
        } else if selectedGroup == "__recientes" {
            let lookup = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            list = recentIDs.compactMap { lookup[$0] }
        } else if let group = selectedGroup, group != "__todos" {
            list = channels.filter { $0.group == group }
        } else {
            list = channels
        }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.name.lowercased().contains(q) || $0.group.lowercased().contains(q) }
        }
        return list
    }

    var selectedChannel: Channel? {
        guard let id = selectedChannelID else { return nil }
        return channels.first { $0.id == id }
    }

    func nowPlaying(_ channel: Channel, at date: Date = Date()) -> Programme? {
        guard let tvg = channel.tvgID, !tvg.isEmpty else { return nil }
        return guide?.nowPlaying(channelID: tvg, at: date)
    }

    func toggleFavoriteFromGuide(_ channel: Channel) { toggleFavorite(channel.id) }
}
