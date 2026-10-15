import Foundation
import Observation
import MacIPTVCore

enum MainTab { case live, guide }

@Observable
@MainActor
final class AppStore {
    var channels: [Channel] = []
    var guide: XMLTVGuide?
    var guideWarning: String?
    var lastError: String?
    var isImporting = false
    var sourceSummary: String?
    var lastUpdatedAt: Date?
    var demoMode = false
    var networkPolicy = NetworkPolicy()
    private var pendingHTTPSource: SavedSource?
    private var pendingHTTPSourceID: UUID?
    private var activeSource: SavedSource?
    private(set) var activeSourceID: UUID?
    var savedSources: [UUID: SavedSource] = [:]
    var resumeLastChannel: Bool { didSet { defaults.set(resumeLastChannel, forKey: "player.resumeLastChannel") } }
    var externalPlayer: String { didSet { defaults.set(externalPlayer, forKey: "player.externalPlayer") } }
    var hideControlsAfter: Int { didSet { defaults.set(hideControlsAfter, forKey: "player.hideControlsAfter") } }
    var needsHTTPConsent: Bool { pendingHTTPSource != nil }
    func authorizeHTTPForPendingSource() {
        guard var saved = pendingHTTPSource else { return }
        saved.policy.allowHTTP = true
        load(saved.source, policy: saved.policy, fileBookmark: saved.fileBookmark,
             sourceID: pendingHTTPSourceID ?? activeSourceID)
    }
    func requestHTTPConsentForPlayback(sourceID: UUID?) {
        guard sourceID != nil, sourceID == activeSourceID,
              let saved = activeSource, !saved.policy.allowHTTP, pendingHTTPSource == nil else { return }
        pendingHTTPSource = saved
        pendingHTTPSourceID = activeSourceID
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
    var reminders: Set<String> {
        didSet { defaults.set(Array(reminders), forKey: "guide.reminders") }
    }
    var searchText = "" { didSet { recentNavigationIDs = nil } }
    /// Centinela visible: una fila con tag nil no puede seleccionarse en List.
    var selectedGroup: String? = "__todos" { didSet { recentNavigationIDs = nil } }
    private var recentNavigationIDs: [String]?
    var favorites: Set<String> = []
    var tab: MainTab = .live
    var showSettings = false
    var searchRequestID = UUID()
    var externalRequestApp: String?
    var confirmRemoveSource = false
    var notice: String?
    private var noticeTask: Task<Void, Never>?
    var showGroups: Bool { didSet { defaults.set(showGroups, forKey: "ui.showGroups") } }
    var showChannels: Bool { didSet { defaults.set(showChannels, forKey: "ui.showChannels") } }
    var fillVideo: Bool { didSet { defaults.set(fillVideo, forKey: "player.fillVideo") } }
    var previewHeight: Double { didSet { defaults.set(previewHeight, forKey: "player.previewHeight") } }
    var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: "ui.appearance") }
    }

    private let keychain = KeychainSourceRepository()
    private let importer = SourceImporter()
    private let channelCache = ChannelCache()
    private let defaultsKey = "favorites.ids"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.showGroups = defaults.object(forKey: "ui.showGroups") as? Bool ?? true
        self.showChannels = defaults.object(forKey: "ui.showChannels") as? Bool ?? true
        self.fillVideo = defaults.object(forKey: "player.fillVideo") as? Bool ?? false
        self.previewHeight = defaults.double(forKey: "player.previewHeight")
        self.resumeLastChannel = defaults.object(forKey: "player.resumeLastChannel") as? Bool ?? true
        self.externalPlayer = defaults.string(forKey: "player.externalPlayer") ?? "VLC"
        self.hideControlsAfter = defaults.object(forKey: "player.hideControlsAfter") as? Int ?? 3
        self.reminders = Set(defaults.stringArray(forKey: "guide.reminders") ?? [])
        self.appearance = AppearancePreference(rawValue: defaults.string(forKey: "ui.appearance") ?? "system") ?? .system
        restoreFavorites(for: nil)
    }

    /// Generacion de importacion: un resultado tardio nunca pisa una fuente
    /// mas nueva, una eliminacion ni el modo demo.
    private var importGeneration = 0
    private var importTask: Task<Void, Never>?

    var hasChannels: Bool { !channels.isEmpty }

    func showNotice(_ message: String) {
        noticeTask?.cancel()
        notice = message
        noticeTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            notice = nil
        }
    }

    func channelCount(for sourceID: UUID) -> Int {
        defaults.integer(forKey: "sources.count." + sourceID.uuidString)
    }

    func updatedAt(for sourceID: UUID) -> Date? {
        defaults.object(forKey: "sources.updated." + sourceID.uuidString) as? Date
    }

    func bootstrap(demo: Bool) {
        restoreFavorites(for: nil)
        if demo {
            // Cambiar a demo invalida cualquier importacion en curso: un
            // resultado tardío no puede pisar el contenido de demostración.
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
        refresh(resumeLastChannel: resumeLastChannel)
    }

    // MARK: Favoritos (UserDefaults: no contienen credenciales)

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        showNotice(favorites.contains(id) ? "Añadido a Favoritos" : "Quitado de Favoritos")
        if favorites.contains(id) { favoriteOrder.append(id) }
        else { favoriteOrder.removeAll { $0 == id } }
        persistNavigation()
        // En demo los favoritos son solo de esta sesion.
        if !demoMode {
            defaults.set(Array(favorites), forKey: navigationKey(defaultsKey))
        }
    }

    private func persistNavigation() {
        guard !demoMode else { return }
        defaults.set(favoriteOrder, forKey: navigationKey("favorites.order"))
        defaults.set(recentIDs, forKey: navigationKey("channels.recent"))
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

    private func navigationKey(_ key: String) -> String {
        guard let activeSourceID else { return key }
        return key + "." + activeSourceID.uuidString
    }

    private func restoreFavorites(for sourceID: UUID?) {
        let suffix = sourceID.map { "." + $0.uuidString } ?? ""
        recentIDs = Array((defaults.stringArray(forKey: "channels.recent" + suffix) ?? []).prefix(20))
        favorites = []
        favoriteOrder = []
        if let ids = defaults.stringArray(forKey: defaultsKey + suffix) {
            favorites = Set(ids)
            favoriteOrder = defaults.stringArray(forKey: "favorites.order" + suffix) ?? ids
            favoriteOrder = favoriteOrder.filter { favorites.contains($0) }
            favoriteOrder.append(contentsOf: ids.filter { !favoriteOrder.contains($0) })
        }
    }

    private func migrateNavigation(to sourceID: UUID) {
        let destination = "favorites.ids." + sourceID.uuidString
        guard defaults.object(forKey: destination) == nil,
              let old = defaults.stringArray(forKey: defaultsKey) else { return }
        defaults.set(old, forKey: destination)
        defaults.set(defaults.stringArray(forKey: "favorites.order") ?? old,
                     forKey: "favorites.order." + sourceID.uuidString)
        defaults.set(defaults.stringArray(forKey: "channels.recent") ?? [],
                     forKey: "channels.recent." + sourceID.uuidString)
    }

    // MARK: Importacion

    /// Reemplaza la fuente solo si la importacion tiene exito; cualquier
    /// fallo deja intactos los canales y la configuracion anteriores.
    func load(_ source: SourceConfiguration, policy: NetworkPolicy = NetworkPolicy(), fileBookmark: Data? = nil,
              persistSource: Bool = true, resumeLastChannel: Bool = false, sourceID: UUID? = nil) {
        let saved = SavedSource(source: source, policy: policy, fileBookmark: fileBookmark)
        let targetID = sourceID ?? UUID()
        let channelToResume = resumeLastChannel
            ? defaults.stringArray(forKey: "channels.recent." + targetID.uuidString)?.first : nil
        pendingHTTPSource = nil
        pendingHTTPSourceID = nil
        importTask?.cancel()
        importGeneration += 1
        let generation = importGeneration
        isImporting = true
        lastError = nil
        importTask = Task { [weak self] in
            guard let self else { return }
            do {
                if !persistSource,
                   let snapshot = try? await self.channelCache.load(sourceID: targetID, source: saved) {
                    guard !Task.isCancelled, generation == self.importGeneration else { return }
                    try await self.publishChannels(
                        ImportOutcome(channels: snapshot.channels, guide: nil, guideWarning: nil, skippedCount: 0),
                        saved: saved, targetID: targetID, persistSource: false,
                        channelToResume: channelToResume, generation: generation, cachedAt: snapshot.savedAt)
                }
                let outcome = try await self.importer.importSource(source, policy: policy, fileBookmark: fileBookmark,
                    onChannelsLoaded: { [weak self] partial in
                        guard let self, !Task.isCancelled, generation == self.importGeneration else {
                            throw CancellationError()
                        }
                        try await self.publishChannels(partial, saved: saved, targetID: targetID,
                                                       persistSource: persistSource,
                                                       channelToResume: channelToResume, generation: generation)
                        try? await self.channelCache.save(channels: partial.channels, sourceID: targetID, source: saved)
                    })
                // Verifica que sigue siendo la importacion vigente.
                guard !Task.isCancelled, generation == self.importGeneration else { return }
                self.guide = outcome.guide
                self.guideWarning = outcome.guideWarning
            } catch IPTVError.httpConsentRequired {
                if generation == self.importGeneration {
                    self.pendingHTTPSource = saved
                    self.pendingHTTPSourceID = targetID
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

    /// Publica la lista antes de esperar al XMLTV. Un resultado tardío de
    /// otra fuente nunca modifica la selección ni la reproducción actuales.
    private func publishChannels(_ outcome: ImportOutcome, saved: SavedSource, targetID: UUID,
                                 persistSource: Bool, channelToResume: String?, generation: Int,
                                 cachedAt: Date? = nil) async throws {
        if persistSource {
            var catalog = KeychainSourceStore.Catalog(sources: savedSources)
            catalog.sources[targetID] = saved
            try await keychain.saveCatalog(catalog)
        }
        guard !Task.isCancelled, generation == importGeneration else { throw CancellationError() }
        demoMode = false
        if activeSourceID == nil && savedSources.count <= 1 { migrateNavigation(to: targetID) }
        let sameSource = activeSourceID == targetID
        let previousGuide = sameSource ? guide : nil
        if !sameSource {
            activeSourceID = targetID
            restoreFavorites(for: targetID)
            selectedChannelID = nil
            previousChannelID = nil
            selectedGroup = "__todos"
        }
        savedSources[targetID] = saved
        defaults.set(targetID.uuidString, forKey: "sources.activeID")
        networkPolicy = saved.policy
        activeSource = saved
        sourceSummary = saved.source.summary
        if let cachedAt {
            channels = outcome.channels
            recentNavigationIDs = nil
            lastUpdatedAt = cachedAt
        } else {
            apply(outcome)
        }
        guide = outcome.guide ?? previousGuide
        defaults.set(outcome.channels.count, forKey: "sources.count." + targetID.uuidString)
        defaults.set(lastUpdatedAt, forKey: "sources.updated." + targetID.uuidString)
        if selectedChannelID == nil, let channelToResume,
           channels.contains(where: { $0.id == channelToResume }) { selectedChannelID = channelToResume }
    }

    func refresh(allowAuthentication: Bool = false, resumeLastChannel: Bool = false) {
        showNotice("Actualizando canales…")
        if let id = activeSourceID, let source = savedSources[id] {
            load(source.source, policy: source.policy, fileBookmark: source.fileBookmark,
                 persistSource: false, resumeLastChannel: resumeLastChannel, sourceID: id)
            return
        }
        importTask?.cancel()
        importGeneration += 1
        let generation = importGeneration
        isImporting = true
        lastError = nil
        importTask = Task { [weak self] in
            guard let self else { return }
            do {
                let catalog = try await self.keychain.loadCatalog(allowAuthentication: allowAuthentication)
                guard !Task.isCancelled, generation == self.importGeneration else { return }
                self.isImporting = false
                self.savedSources = catalog.sources
                let preferred = self.defaults.string(forKey: "sources.activeID").flatMap(UUID.init(uuidString:))
                if let id = preferred.flatMap({ catalog.sources[$0] == nil ? nil : $0 }) ??
                    catalog.sources.keys.sorted(by: { $0.uuidString < $1.uuidString }).first,
                   let source = catalog.sources[id] {
                    self.load(source.source, policy: source.policy, fileBookmark: source.fileBookmark,
                              persistSource: false, resumeLastChannel: resumeLastChannel, sourceID: id)
                }
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
        lastUpdatedAt = Date()
        let live = Set(outcome.channels.map(\.id))
        favorites.formIntersection(live)
        favoriteOrder.removeAll { !live.contains($0) }
        recentIDs.removeAll { !live.contains($0) }
        if let previous = previousChannelID, !live.contains(previous) { previousChannelID = nil }
        persistNavigation()
        if !demoMode {
            defaults.set(Array(favorites), forKey: navigationKey(defaultsKey))
        }
        if let selected = selectedChannelID, !live.contains(selected) {
            selectedChannelID = nil
        }
    }

    func activateSource(_ id: UUID) {
        guard let saved = savedSources[id] else { return }
        load(saved.source, policy: saved.policy, fileBookmark: saved.fileBookmark,
             persistSource: false, resumeLastChannel: resumeLastChannel, sourceID: id)
    }

    func removeSource(_ id: UUID? = nil) {
        guard let targetID = id ?? activeSourceID, savedSources[targetID] != nil else { return }
        var catalog = KeychainSourceStore.Catalog(sources: savedSources)
        catalog.sources.removeValue(forKey: targetID)
        let wasActive = activeSourceID == targetID
        importTask?.cancel()
        importGeneration += 1
        let generation = importGeneration
        lastError = nil
        isImporting = true
        importTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.keychain.saveCatalog(catalog)
                try? await self.channelCache.remove(sourceID: targetID)
                guard !Task.isCancelled, generation == self.importGeneration else { return }
                self.savedSources = catalog.sources
                if !wasActive {
                    self.isImporting = false
                    return
                }
                self.activeSource = nil
                self.pendingHTTPSource = nil
                self.pendingHTTPSourceID = nil
                self.activeSourceID = nil
                self.defaults.removeObject(forKey: "sources.activeID")
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
                self.selectedGroup = "__todos"
                if let next = catalog.sources.keys.sorted(by: { $0.uuidString < $1.uuidString }).first {
                    self.activateSource(next)
                }
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
        pendingHTTPSourceID = nil
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
            if idx + delta < 0 { showNotice("Primer canal de la lista") }
            if idx + delta >= list.count { showNotice("Último canal de la lista") }
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
        sourceSummary = "Modo demostración"
        lastUpdatedAt = Date()
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
            list = list.filter {
                $0.name.lowercased().contains(q) ||
                ChannelName($0.name).title.lowercased().contains(q) ||
                $0.group.lowercased().contains(q)
            }
        }
        return list
    }

    var selectedChannel: Channel? {
        guard let id = selectedChannelID else { return nil }
        return channels.first { $0.id == id }
    }

    var previousVisibleChannel: Channel? {
        guard let index = visibleChannels.firstIndex(where: { $0.id == selectedChannelID }), index > 0 else { return nil }
        return visibleChannels[index - 1]
    }

    var nextVisibleChannel: Channel? {
        guard let index = visibleChannels.firstIndex(where: { $0.id == selectedChannelID }),
              index + 1 < visibleChannels.count else { return nil }
        return visibleChannels[index + 1]
    }

    func nowPlaying(_ channel: Channel, at date: Date = Date()) -> Programme? {
        guard let tvg = channel.tvgID, !tvg.isEmpty else { return nil }
        return guide?.nowPlaying(channelID: tvg, at: date)
    }

    func toggleFavoriteFromGuide(_ channel: Channel) { toggleFavorite(channel.id) }

    func reminderKey(channel: Channel, programme: Programme) -> String {
        "\(activeSourceID?.uuidString ?? "demo")|\(channel.id)|\(Int(programme.start.timeIntervalSince1970))"
    }

    func toggleReminder(channel: Channel, programme: Programme) {
        let key = reminderKey(channel: channel, programme: programme)
        if !reminders.insert(key).inserted { reminders.remove(key) }
    }
}
