import SwiftUI
import AppKit
import MacIPTVCore

/// Dispositivo persistente de tres paneles: grupos, canales y reproductor/guia.
struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var bannerVisible = false

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            HSplitView {
                ChannelListView()
                    .frame(minWidth: 260, idealWidth: 290, maxWidth: 320)
                VStack(spacing: 0) {
                    if store.showGuide, let guide = store.guide {
                        GuideView(channels: store.visibleChannels, guide: guide) { channel in
                            store.selectedChannelID = channel.id
                            store.showGuide = false
                        }
                    } else {
                        playerPane
                        programInfo
                    }
                }
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $store.showSettings) {
            SourceSettingsSheet()
                .environment(store)
        }
        .toolbar { toolbarItems }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .alert("Error al cargar", isPresented: Binding(get: { store.lastError != nil },
                                                       set: { if !$0 { store.lastError = nil } })) {
            Button("Aceptar", role: .cancel) { store.lastError = nil }
            Button("Reintentar") { store.refresh() }
            if store.lastError?.contains("Llavero") == true {
                Button("Autorizar llavero") { store.refresh(allowAuthentication: true) }
            }
        } message: {
            Text(store.lastError ?? "")
        }
        .preferredColorScheme(.dark)
        .tint(Color(red: 0.45, green: 0.90, blue: 0.75))
    }

    // MARK: Panel lateral de grupos

    private var sidebar: some View {
        @Bindable var store = store
        return List(selection: $store.selectedGroup) {
            Section {
                Button { store.selectedGroup = "__todos" } label: {
                    Label("Todos los canales", systemImage: "list.dash")
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .tag(Optional<String>("__todos"))
                Button { store.selectedGroup = "__favoritos" } label: {
                    Label("Favoritos", systemImage: "star.fill")
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .tag(Optional<String>("__favoritos"))
            }
            Section {
                Button { store.selectedGroup = "__recientes" } label: {
                    Label("Recientes", systemImage: "clock")
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).tag(Optional<String>("__recientes"))
            }
            if !store.groups.isEmpty {
                Section("Grupos") {
                    ForEach(store.groups, id: \.self) { group in
                        Button { store.selectedGroup = group } label: {
                            Text(group).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).tag(Optional<String>(group))
                    }
                }
            }
        }
        .searchable(text: $store.searchText, placement: .sidebar, prompt: "Buscar canales")
        .overlay {
            if !store.hasChannels && !store.isImporting {
                VStack(spacing: 12) {
                    ContentUnavailableView("Sin canales",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Conecta tu proveedor o prueba la demostracion."))
                    Button("Probar demo") { store.startDemo() }
                        .buttonStyle(.borderedProminent)
                    Button("Conectar proveedor") { store.showSettings = true }
                }
                .padding()
            }
        }
    }

    // MARK: Reproductor y programa actual

    @ViewBuilder private var playerPane: some View {
        PlayerView(channel: store.selectedChannel)
            .overlay(alignment: .topLeading) {
                if bannerVisible, let channel = store.selectedChannel {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.name).font(.headline)
                        if let programme = store.nowPlaying(channel) {
                            Text(programme.title).font(.subheadline)
                        }
                    }
                    .padding(12)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                    .padding(16)
                    .allowsHitTesting(false)
                }
            }
            .task(id: store.selectedChannelID) {
                bannerVisible = store.selectedChannelID != nil
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                bannerVisible = false
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable()
            .onMoveCommand { direction in
                switch direction {
                case .up: store.moveSelection(by: -1)
                case .down: store.moveSelection(by: 1)
                default: break
                }
            }
    }

    @ViewBuilder private var programInfo: some View {
        if let channel = store.selectedChannel {
            HStack(spacing: 8) {
                Text(channel.name).font(.headline)
                if store.favorites.contains(channel.id) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }
                if let programme = store.nowPlaying(channel) {
                    Text("-").foregroundStyle(.secondary)
                    Text(programme.title)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { store.returnToPreviousChannel() } label: {
                Label("Canal anterior", systemImage: "arrow.uturn.backward")
            }
            .disabled(store.previousChannelID == nil)
            .help("Volver al canal anterior (⌥⌘←)")
            Button {
                store.showGuide.toggle()
            } label: {
                Label("Guia", systemImage: "calendar.day.timeline.left")
            }
            .disabled(store.guide == nil)
            .help("Guia de programacion")

            Button {
                store.refresh()
            } label: {
                Label("Actualizar", systemImage: "arrow.clockwise")
            }
            .disabled(!store.hasChannels || store.isImporting)

            Button {
                store.showSettings = true
            } label: {
                Label("Fuente", systemImage: "server.rack")
            }
            .help("Configurar la fuente del proveedor")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Abrir diagnostico") { NSWorkspace.shared.open(DiagnosticLog.fileURL) }
                if let channel = store.selectedChannel {
                    Button("Abrir en VLC") {
                        if !ExternalPlayer.open(channel.url, app: "VLC") {
                            store.lastError = "VLC no esta instalado. Instalalo desde videolan.org para abrir este canal."
                        }
                    }
                    .disabled(!ExternalPlayer.isInstalled("VLC"))
                    Button("Abrir en IINA") {
                        if !ExternalPlayer.open(channel.url, app: "IINA") {
                            store.lastError = "IINA no esta instalado. Instalalo desde iina.io para abrir este canal."
                        }
                    }
                    .disabled(!ExternalPlayer.isInstalled("IINA"))
                    Divider()
                }
                Button("Quitar fuente", role: .destructive) { store.removeSource() }
                    .disabled(!store.hasChannels)
            } label: {
                Label("Mas", systemImage: "ellipsis.circle")
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if let summary = store.sourceSummary {
                Label(summary, systemImage: store.demoMode ? "sparkles" : "lock.shield")
            }
            Spacer()
            if let warning = store.guideWarning {
                Text(warning).foregroundStyle(.orange).lineLimit(1)
            }
            if store.isImporting {
                ProgressView().controlSize(.small)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}

/// Panel medio siempre visible: clic para reproducir, estrella para favorito.
struct ChannelListView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        return List {
            ForEach(store.visibleChannels) { channel in
                HStack {
                    Button {
                        store.selectedChannelID = channel.id
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(channel.name)
                                .foregroundStyle(.primary)
                            if let programme = store.nowPlaying(channel) {
                                Text(programme.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        // Toda la anchura restante de la fila es zona pulsable;
                        // la estrella sigue siendo un boton aparte.
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        store.toggleFavorite(channel.id)
                    } label: {
                        Image(systemName: store.favorites.contains(channel.id) ? "star.fill" : "star")
                    }
                    .buttonStyle(.borderless)
                    .help("Favorito")
                }
                .contextMenu {
                    if store.favorites.contains(channel.id) {
                        Button("Subir favorito") { store.moveFavorite(channel.id, by: -1) }
                            .disabled(store.favoriteOrder.first == channel.id)
                        Button("Bajar favorito") { store.moveFavorite(channel.id, by: 1) }
                            .disabled(store.favoriteOrder.last == channel.id)
                    }
                }
                .listRowBackground(store.selectedChannelID == channel.id
                                   ? Color.accentColor.opacity(0.25) : Color.clear)
            }
        }
        .onMoveCommand { direction in
            switch direction {
            case .up: store.moveSelection(by: -1)
            case .down: store.moveSelection(by: 1)
            default: break
            }
        }
        .overlay {
            if store.visibleChannels.isEmpty && store.hasChannels {
                ContentUnavailableView("Nada que mostrar", systemImage: "magnifyingglass")
            }
        }
    }
}

/// Alternativa explicita para canales incompatibles con AVKit (p. ej. TS directo).
enum ExternalPlayer {
    private static func bundleID(for app: String) -> String {
        app == "VLC" ? "org.videolan.vlc" : "com.colliderli.iina"
    }

    /// Solo NSWorkspace (sin AppleScript): permite desactivar la opcion si la
    /// app no esta instalada en lugar de fallar en silencio.
    static func isInstalled(_ app: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID(for: app)) != nil
    }

    @discardableResult
    static func open(_ streamURL: String, app: String) -> Bool {
        guard let url = URL(string: streamURL) else { return false }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID(for: app)) else {
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
        return true
    }
}
