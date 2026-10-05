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
    var selectedChannelID: String?
    var searchText = ""
    /// Centinela visible: una fila con tag nil no puede seleccionarse en List.
    var selectedGroup: String? = "__todos"
    var favorites: Set<String> = []
    var showGuide = false
    var showSettings = false

    private let keychain = KeychainSourceRepository()
    private let importer = SourceImporter()
    private let defaultsKey = "favorites.ids"

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
            applyDemo()
            return
        }
        refresh()
    }

    // MARK: Favoritos (UserDefaults: no contienen credenciales)

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        // En demo los favoritos son solo de esta sesion.
        if !demoMode {
            UserDefaults.standard.set(Array(favorites), forKey: defaultsKey)
        }
    }

    private func restoreFavorites() {
        if let ids = UserDefaults.standard.stringArray(forKey: defaultsKey) {
            favorites = Set(ids)
        }
    }

    // MARK: Importacion

    /// Reemplaza la fuente solo si la importacion tiene exito; cualquier
    /// fallo deja intactos los canales y la configuracion anteriores.
    func load(_ source: SourceConfiguration) {
        importTask?.cancel()
        importGeneration += 1
        let generation = importGeneration
        isImporting = true
        lastError = nil
        importTask = Task { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await self.importer.importSource(source)
                // Verifica que sigue siendo la importacion vigente.
                guard !Task.isCancelled, generation == self.importGeneration else { return }
                // Primero persiste la configuracion; si el Llavero falla,
                // conserva canales y fuente previos.
                try await self.keychain.save(source)
                guard !Task.isCancelled, generation == self.importGeneration else { return }
                // Cargar una fuente real desde demo sale del modo demo.
                if self.demoMode {
                    self.demoMode = false
                    self.restoreFavorites()
                }
                self.selectedGroup = "__todos"
                self.apply(outcome)
                self.sourceSummary = source.summary
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
                let source = try await self.keychain.load(allowAuthentication: allowAuthentication)
                guard !Task.isCancelled, generation == self.importGeneration else { return }
                self.isImporting = false
                if let source { self.load(source) }
            } catch {
                guard !Task.isCancelled, generation == self.importGeneration else { return }
                self.lastError = (error as? LocalizedError)?.errorDescription ?? "No se pudo leer la fuente guardada."
                self.isImporting = false
            }
        }
    }

    private func apply(_ outcome: ImportOutcome) {
        channels = outcome.channels
        guide = outcome.guide
        guideWarning = outcome.guideWarning
        let live = Set(outcome.channels.map(\.id))
        favorites.formIntersection(live)
        if !demoMode {
            UserDefaults.standard.set(Array(favorites), forKey: defaultsKey)
        }
        if let selected = selectedChannelID, !live.contains(selected) {
            selectedChannelID = nil
        }
    }

    func removeSource() {
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
                self.selectedGroup = "__todos"
                UserDefaults.standard.removeObject(forKey: self.defaultsKey)
            } catch {
                guard !Task.isCancelled, generation == self.importGeneration else { return }
                self.lastError = (error as? LocalizedError)?.errorDescription ?? "No se pudo quitar la fuente."
            }
            if generation == self.importGeneration { self.isImporting = false }
        }
    }

    func startDemo() {
        importTask?.cancel()
        importGeneration += 1
        isImporting = false
        lastError = nil
        demoMode = true
        applyDemo()
    }

    /// Sube o baja la seleccion dentro de la lista visible (teclado).
    func moveSelection(by delta: Int) {
        let list = visibleChannels
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
        selectedChannelID = nil
    }

    // MARK: Listas derivadas

    var groups: [String] {
        var seen = Set<String>()
        return channels.map(\.group).filter { seen.insert($0).inserted }.sorted()
    }

    var visibleChannels: [Channel] {
        var list: [Channel]
        if selectedGroup == "__favoritos" {
            list = channels.filter { favorites.contains($0.id) }
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

    func nowPlaying(_ channel: Channel) -> Programme? {
        guard let tvg = channel.tvgID, !tvg.isEmpty else { return nil }
        return guide?.nowPlaying(channelID: tvg, at: Date())
    }

    func toggleFavoriteFromGuide(_ channel: Channel) { toggleFavorite(channel.id) }
}
