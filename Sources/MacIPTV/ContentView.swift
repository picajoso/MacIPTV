import SwiftUI
import AppKit
import MacIPTVCore

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @State private var externalRequest: ExternalRequest?
    @State private var programmeSelection: ProgrammeSelection?
    @State private var isFullScreen = false
    @State private var fullScreenDrawerOpen = false
    @State private var previewDragStartHeight: CGFloat?
    @State private var previewDragHeight: CGFloat?
    @FocusState private var searchFocused: Bool

    private struct ExternalRequest: Identifiable {
        let id = UUID()
        let url: String
        let app: String
    }

    /// Pantalla completa del sistema o modo solo vídeo dentro de la ventana:
    /// ambos ocultan paneles y usan los controles superpuestos.
    private var immersive: Bool { isFullScreen || store.videoOnly }

    var body: some View {
        @Bindable var store = store
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if !immersive {
                    titleBar
                    Rectangle().fill(Theme.divider).frame(height: 2)
                }
                HStack(spacing: 0) {
                    if store.showGroups && !immersive {
                        sidebar.frame(width: 229)
                        Rectangle().fill(Theme.divider).frame(width: 2)
                    }
                    ZStack {
                        HStack(spacing: 0) {
                            if store.showChannels && store.tab == .live && !immersive {
                                ChannelListView(onExternal: requestExternal, onFullScreen: enterFullScreen)
                                    .frame(width: 329)
                                Rectangle().fill(Theme.divider).frame(width: 2)
                            }
                            videoColumn
                        }
                        .opacity(store.tab == .guide && !immersive ? 0 : 1)
                        .allowsHitTesting(store.tab != .guide || immersive)
                        if store.tab == .guide && !immersive, let guide = store.guide {
                            GuideView(channels: store.visibleChannels, guide: guide) { channel in
                                store.selectedChannelID = channel.id
                                store.tab = .live
                            }
                        }
                    }
                }
                if !immersive { statusBar }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(immersive ? Color.black : Theme.bg)
            .foregroundStyle(Theme.fg)
        }
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $store.showSettings) {
            SourceSettingsSheet().environment(store)
        }
        .sheet(item: $programmeSelection) { selection in
            if let guide = store.guide {
                ProgrammeDetailView(selection: selection, guide: guide) { channel in
                    store.selectedChannelID = channel.id
                    store.tab = .live
                }
                .environment(store)
            }
        }
        .alert("Error al cargar", isPresented: Binding(get: { store.lastError != nil },
                                                       set: { if !$0 { store.lastError = nil } })) {
            Button("Aceptar", role: .cancel) { store.lastError = nil }
            Button("Reintentar") { store.refresh() }
            if store.needsHTTPConsent {
                Button("Permitir HTTP para esta fuente") { store.authorizeHTTPForPendingSource() }
            }
            if store.lastError?.contains("Llavero") == true {
                Button("Autorizar llavero") { store.refresh(allowAuthentication: true) }
            }
        } message: { Text(store.lastError ?? "") }
        .sheet(item: $externalRequest) { request in
            ConfirmationSheet(
                title: "Abrir en \(request.app)",
                message: "La URL del canal puede incluir tus credenciales. \(request.app) recibirá esa URL y podrá guardarla en su historial. Sus conexiones no pasan por las protecciones de MacIPTV.",
                actionTitle: "Abrir"
            ) {
                if !ExternalPlayer.open(request.url, app: request.app) {
                    store.lastError = "No se pudo abrir \(request.app)."
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in isFullScreen = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
            fullScreenDrawerOpen = false
        }
        .onExitCommand {
            if isFullScreen { enterFullScreen() } else if store.videoOnly { store.videoOnly = false }
        }
        .onChange(of: store.tab) { _, tab in if tab == .guide { store.videoOnly = false } }
        .onChange(of: store.videoOnly) { _, value in if !value && !isFullScreen { fullScreenDrawerOpen = false } }
        .overlay(alignment: .bottom) {
            if let notice = store.notice {
                Text(notice).font(Archivo.font(13, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(Theme.fg).foregroundStyle(Theme.bg)
                    .padding(.bottom, immersive ? 70 : 30)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: store.searchRequestID) { _, _ in searchFocused = true }
        .onChange(of: store.externalRequestApp) { _, app in
            if let app, let channel = store.selectedChannel {
                requestExternal(channel, app)
                store.externalRequestApp = nil
            }
        }
        .sheet(isPresented: $store.confirmRemoveSource) {
            ConfirmationSheet(title: "Quitar fuente",
                              message: "La fuente activa se quitará del Llavero. Los demás proveedores permanecerán guardados.",
                              actionTitle: "Quitar fuente") { store.removeSource() }
        }
        .tint(Theme.accent)
    }

    private var firstSectionWidth: CGFloat {
        if store.showGroups { return 230 }
        if store.showChannels || store.tab == .guide { return 330 }
        return 184
    }

    private var secondSectionWidth: CGFloat {
        store.tab == .guide || store.showChannels ? 330 : 52
    }

    private var titleBar: some View {
        HStack(spacing: 0) {
            ZStack {
                WindowDragRegion()
                HStack(spacing: 0) {
                    Color.clear.frame(width: 70)
                    titleButton(store.showGroups ? "panel-left-close" : "panel-left-open",
                                label: store.showGroups ? "Ocultar grupos" : "Mostrar grupos",
                                help: "\(store.showGroups ? "Ocultar" : "Mostrar") grupos (⌃⌘S)") {
                        withAnimation(.easeInOut(duration: 0.2)) { store.showGroups.toggle() }
                    }
                    Text("MacIPTV")
                        .font(Archivo.font(18, weight: .heavy))
                        .tracking(-0.36)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.leading, 6)
                    Spacer(minLength: 0)
                }
            }
            .frame(width: firstSectionWidth, height: 52)
            titleDivider
            HStack(spacing: 4) {
                titleButton(store.showChannels ? "columns-2" : "square",
                            label: store.showChannels ? "Ocultar lista de canales" : "Mostrar lista de canales",
                            help: "\(store.showChannels ? "Ocultar" : "Mostrar") lista de canales (⌃⌘L)",
                            disabled: store.tab == .guide) {
                    withAnimation(.easeInOut(duration: 0.2)) { store.showChannels.toggle() }
                }
                if store.tab == .guide || store.showChannels {
                    LucideIcon(name: "search", size: 16)
                    ZStack(alignment: .leading) {
                        if store.searchText.isEmpty {
                            Text("Buscar en \(groupTitle)")
                                .foregroundStyle(Theme.onRed.opacity(0.85))
                                .allowsHitTesting(false)
                        }
                        TextField("", text: Binding(get: { store.searchText }, set: { store.searchText = $0 }))
                            .textFieldStyle(.plain)
                            .focused($searchFocused)
                            .foregroundStyle(Theme.onRed)
                            .accessibilityLabel("Buscar canales")
                    }
                    .font(Archivo.font(13))
                    if !store.searchText.isEmpty {
                        Button { store.searchText = "" } label: { LucideIcon(name: "x", size: 15) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Limpiar búsqueda")
                            .help("Limpiar búsqueda")
                    }
                    Spacer(minLength: 12)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .frame(width: secondSectionWidth, height: 52, alignment: .leading)
            titleDivider
            HStack(spacing: 0) {
                tabButton("Directo", icon: "radio", shortcut: "⌘1", tab: .live)
                tabButton("Guía", icon: "calendar-days", shortcut: "⌘2", tab: .guide)
                Spacer(minLength: 0)
                titleButton("undo-2", label: "Volver al canal anterior", help: "Último canal (⌥⌘←)",
                            disabled: store.previousChannelID == nil) { store.returnToPreviousChannel() }
                titleButton("refresh-cw", label: "Actualizar canales", help: "Actualizar canales (⌘R)",
                            disabled: !store.hasChannels || store.isImporting) { store.refresh() }
                titleButton("settings", label: "Ajustes", help: "Ajustes (⌘,)") { openSettings() }
                Menu {
                    if let channel = store.selectedChannel {
                        Button("Abrir en VLC") { requestExternal(channel, "VLC") }
                            .disabled(!ExternalPlayer.isInstalled("VLC"))
                        Button("Abrir en IINA") { requestExternal(channel, "IINA") }
                            .disabled(!ExternalPlayer.isInstalled("IINA"))
                    }
                    Button("Abrir diagnóstico") { NSWorkspace.shared.open(DiagnosticLog.fileURL) }
                    Divider()
                    Button("Quitar fuente", role: .destructive) { store.confirmRemoveSource = true }
                        .disabled(!store.hasChannels)
                } label: { LucideIcon(name: "ellipsis", size: 18).frame(width: 40, height: 52) }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel("Más opciones")
                    .help("Más opciones")
            }
        }
        .frame(height: 52)
        .background(Theme.accent)
        .foregroundStyle(Theme.onRed)
    }

    private var titleDivider: some View {
        Rectangle().fill(Theme.onRed.opacity(0.5)).frame(width: 1, height: 52)
    }

    private func titleButton(_ icon: String, label: String, help: String,
                             disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { LucideIcon(name: icon, size: 18).frame(width: 40, height: 52) }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled ? 0.45 : 1)
            .accessibilityLabel(label)
            .help(help)
    }

    private func tabButton(_ title: String, icon: String, shortcut: String, tab: MainTab) -> some View {
        Button { store.tab = tab } label: {
            HStack(spacing: 8) {
                LucideIcon(name: icon, size: 16)
                Text(title).font(Archivo.font(13, weight: store.tab == tab ? .heavy : .semibold))
                Text(shortcut).font(Archivo.font(10.5)).opacity(0.6)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(store.tab == tab ? Theme.bg : Color.clear)
            .foregroundStyle(store.tab == tab ? Theme.fg : Theme.onRed)
        }
        .buttonStyle(.plain)
        .help("\(title) (\(shortcut))")
    }

    private var groupTitle: String {
        switch store.selectedGroup {
        case "__todos", nil: "Todos los canales"
        case "__favoritos": "Favoritos"
        case "__recientes": "Recientes"
        case .some(let name): name
        }
    }

    private var sidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                groupRow("Todos los canales", icon: "list", group: "__todos", count: store.channels.count)
                groupRow("Favoritos", icon: "heart", group: "__favoritos", count: store.favoriteOrder.count)
                groupRow("Recientes", icon: "history", group: "__recientes", count: store.recentIDs.count)
                if !store.groups.isEmpty {
                    Text("GRUPOS")
                        .font(Archivo.font(10)).tracking(1).foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
                    ForEach(store.groups, id: \.self) { group in
                        groupRow(group, icon: "folder", group: group,
                                 count: store.channels.filter { $0.group == group }.count)
                    }
                }
            }
        }
        .background(Theme.bg)
    }

    private func groupRow(_ title: String, icon: String, group: String, count: Int) -> some View {
        let selected = store.selectedGroup == group
        return Button { store.selectedGroup = group } label: {
            HStack(spacing: 10) {
                LucideIcon(name: icon, size: 15)
                    .foregroundStyle(icon == "heart" && !selected ? Theme.accent : (selected ? Theme.selectedFg : Theme.fg))
                Text(title).font(Archivo.font(13, weight: selected ? .heavy : .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(count)").font(Archivo.font(10.5)).opacity(0.65)
            }
            .padding(.leading, 16).padding(.trailing, 12)
            .frame(height: 34).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.selected : Theme.bg)
            .foregroundStyle(selected ? Theme.selectedFg : Theme.fg)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var videoColumn: some View {
        GeometryReader { geometry in
            let naturalHeight = min(geometry.size.width * 9 / 16, 470)
            let minimumHeight = min(150, max(100, geometry.size.height - 140))
            let maximumHeight = max(minimumHeight, geometry.size.height - 24 - 120)
            let requestedHeight = previewDragHeight ?? (store.previewHeight > 0 ? CGFloat(store.previewHeight) : naturalHeight)
            let playerHeight = immersive
                ? geometry.size.height
                : min(max(requestedHeight, minimumHeight), maximumHeight)
            VStack(spacing: 0) {
                PlayerView(channel: store.selectedChannel,
                           programme: store.selectedChannel.flatMap { store.nowPlaying($0) },
                           programmeEnd: store.selectedChannel.flatMap { store.nowPlaying($0) }.flatMap { store.guide?.effectiveEnd(of: $0) },
                           isFullScreen: immersive,
                           isVideoOnly: store.videoOnly && !isFullScreen,
                           fillVideo: immersive && store.fillVideo,
                           hideControlsAfter: store.hideControlsAfter,
                           isFavorite: store.selectedChannelID.map { store.favorites.contains($0) } ?? false,
                           previousChannelName: store.previousVisibleChannel.map { ChannelName($0.name).title },
                           nextChannelName: store.nextVisibleChannel.map { ChannelName($0.name).title },
                           onPrevious: { store.moveSelection(by: -1) },
                           onNext: { store.moveSelection(by: 1) },
                           onFavorite: { if let id = store.selectedChannelID { store.toggleFavorite(id) } },
                           onToggleFill: { store.fillVideo.toggle() },
                           onToggleDrawer: { fullScreenDrawerOpen.toggle() },
                           onToggleVideoOnly: { store.videoOnly.toggle() },
                           onExternal: { if let channel = store.selectedChannel { requestExternal(channel, store.externalPlayer) } },
                           networkPolicy: store.networkPolicy,
                           sourceID: store.activeSourceID,
                           onHTTPConsentRequired: { store.requestHTTPConsentForPlayback(sourceID: store.activeSourceID) })
                    .frame(width: geometry.size.width, height: playerHeight)
                    .frame(maxWidth: .infinity).background(.black)
                    .focusable()
                    .onMoveCommand { direction in
                        switch direction {
                        case .up: store.moveSelection(by: -1)
                        case .down: store.moveSelection(by: 1)
                        default: break
                        }
                    }
                if !immersive {
                    if store.tab == .live {
                        PreviewResizeControl(
                            onDecrease: { store.previewHeight = Double(max(minimumHeight, playerHeight - 36)) },
                            onIncrease: { store.previewHeight = Double(min(maximumHeight, playerHeight + 36)) },
                            onDragChanged: { translation in
                                let start = previewDragStartHeight ?? playerHeight
                                previewDragStartHeight = start
                                previewDragHeight = min(max(start + translation, minimumHeight), maximumHeight)
                            },
                            onDragEnded: {
                                if let previewDragHeight { store.previewHeight = Double(previewDragHeight) }
                                previewDragStartHeight = nil
                                previewDragHeight = nil
                            }
                        )
                        .frame(height: 24)
                    } else {
                        Rectangle().fill(Theme.divider).frame(height: 2)
                    }
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            programmeInfo
                            actionStrip
                            laterToday
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .trailing) {
                if immersive && fullScreenDrawerOpen { fullScreenDrawer }
            }
            .overlay(alignment: .top) {
                // Sin barra de título, esta franja permite mover la ventana.
                if store.videoOnly && !isFullScreen { WindowDragRegion().frame(height: 28) }
            }
        }
    }

    private var fullScreenDrawer: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(store.visibleChannels.count) CANALES")
                        .font(Archivo.font(10)).tracking(1).foregroundStyle(Theme.accentOnDark)
                    Text(groupTitle).font(Archivo.font(16, weight: .heavy))
                }
                Spacer()
                Button { fullScreenDrawerOpen = false } label: { LucideIcon(name: "x", size: 18) }
                    .accessibilityLabel("Cerrar canales")
                    .help("Cerrar canales")
            }
            .padding(16)
            .frame(height: 72)
            .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.25)).frame(height: 1) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.visibleChannels) { channel in
                        Button { store.selectedChannelID = channel.id } label: {
                            HStack(spacing: 10) {
                                ChannelLogo(channel: channel, size: 36)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ChannelName(channel.name).title)
                                        .font(Archivo.font(13, weight: .heavy)).lineLimit(1)
                                    Text(store.nowPlaying(channel)?.title ?? "Sin programación")
                                        .font(Archivo.font(11)).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 58)
                            .background(store.selectedChannelID == channel.id
                                        ? Color(red: 58/255, green: 26/255, blue: 20/255) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .background(Color(red: 26/255, green: 24/255, blue: 23/255))
        .foregroundStyle(.white)
        .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.3)).frame(width: 2) }
    }

    private var programmeInfo: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 0) {
                programmeCell("AHORA", programme: store.selectedChannel.flatMap { store.nowPlaying($0, at: context.date) },
                              date: context.date)
                Rectangle().fill(Theme.divider).frame(width: 1)
                programmeCell("DESPUÉS", programme: nextProgramme(after: context.date), date: context.date)
            }
            .frame(height: 100)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 2) }
        }
    }

    private func programmeCell(_ label: String, programme: Programme?, date: Date) -> some View {
        Button {
            if let channel = store.selectedChannel, let programme {
                programmeSelection = ProgrammeSelection(channel: channel, programme: programme)
            }
        } label: {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(Archivo.font(10)).tracking(1)
                .foregroundStyle(label == "AHORA" ? Theme.accentText : Theme.muted)
            Text(programme?.title ?? "Sin programación")
                .font(Archivo.font(label == "AHORA" ? 16 : 14, weight: label == "AHORA" ? .heavy : .regular))
                .lineLimit(2)
            if let programme, let end = store.guide?.effectiveEnd(of: programme), label == "AHORA" {
                Text("quedan \(Int(max(0, end.timeIntervalSince(date)) / 60)) min")
                    .font(Archivo.font(11.5)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(programme == nil)
        .help(label == "AHORA" ? "Ver programa actual" : "Ver programa siguiente")
    }

    private func nextProgramme(after date: Date) -> Programme? {
        guard let channel = store.selectedChannel, let tvgID = channel.tvgID else { return nil }
        return store.guide?.programmes(for: tvgID).first { $0.start > date }
    }

    private var actionStrip: some View {
        HStack(spacing: 0) {
            actionCell("Anterior", icon: "chevron-up", shortcut: "⌥⌘↑") { store.moveSelection(by: -1) }
            actionCell("Siguiente", icon: "chevron-down", shortcut: "⌥⌘↓") { store.moveSelection(by: 1) }
            actionCell("Último", icon: "undo-2", shortcut: "⌥⌘←",
                       disabled: store.previousChannelID == nil) { store.returnToPreviousChannel() }
            actionCell("Favorito", icon: "heart", shortcut: "⌘D",
                       disabled: store.selectedChannelID == nil) {
                if let id = store.selectedChannelID { store.toggleFavorite(id) }
            }
            actionCell("Abrir en \(store.externalPlayer)", icon: "external-link", shortcut: "",
                       disabled: store.selectedChannel == nil || !ExternalPlayer.isInstalled(store.externalPlayer)) {
                if let channel = store.selectedChannel { requestExternal(channel, store.externalPlayer) }
            }
        }
        .frame(height: 54)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 2) }
    }

    private func actionCell(_ title: String, icon: String, shortcut: String,
                            disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    LucideIcon(name: icon, size: 17)
                    Text(title).font(Archivo.font(12.5, weight: .semibold)).lineLimit(1)
                }
                Text(shortcut).font(Archivo.font(10)).foregroundStyle(Theme.muted)
            }
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.divider).frame(width: 1) }
        }
        .buttonStyle(.plain).disabled(disabled)
        .foregroundStyle(disabled ? Theme.faint : Theme.fg)
        .help(shortcut.isEmpty ? title : "\(title) (\(shortcut))")
    }

    private var laterToday: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Más tarde hoy").font(Archivo.font(13, weight: .heavy))
                Spacer()
                Button("Abrir guía ⌘2") { store.tab = .guide }
                    .buttonStyle(.plain).font(Archivo.font(12)).foregroundStyle(Theme.accentText)
            }
            .padding(.horizontal, 16).frame(height: 38)
            if let channel = store.selectedChannel, let tvgID = channel.tvgID {
                ForEach(Array((store.guide?.programmes(for: tvgID) ?? [])
                    .filter { $0.start > Date() }.prefix(6)), id: \.start) { programme in
                    Button {
                        programmeSelection = ProgrammeSelection(channel: channel, programme: programme)
                    } label: {
                    HStack(spacing: 8) {
                        Text(programme.start, format: .dateTime.hour().minute())
                            .font(Archivo.font(12, weight: .semibold)).frame(width: 64, alignment: .leading)
                        Text(programme.title).font(Archivo.font(13)).lineLimit(1)
                        Spacer()
                        if store.reminders.contains(store.reminderKey(channel: channel, programme: programme)) {
                            LucideIcon(name: "bell-ring", size: 16).foregroundStyle(Theme.accent)
                        } else {
                            LucideIcon(name: "bell", size: 16).foregroundStyle(Theme.faint)
                        }
                    }
                    .padding(.horizontal, 16).frame(height: 38)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            LucideIcon(name: store.demoMode ? "sparkles" : "shield-check", size: 13)
            Text("\(store.sourceSummary ?? "Sin fuente") · \(store.channels.count) canales" +
                 (store.lastUpdatedAt.map { " · hoy " + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
                .lineLimit(1)
            Spacer(minLength: 8)
            if store.isImporting {
                ProgressView().controlSize(.small)
            } else if let warning = store.guideWarning {
                Text(warning).foregroundStyle(Theme.accentText).lineLimit(1)
            }
        }
        .font(Archivo.font(11)).foregroundStyle(Theme.muted)
        .padding(.horizontal, 12).frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 2) }
    }

    private func requestExternal(_ channel: Channel, _ app: String) {
        externalRequest = ExternalRequest(url: channel.url, app: app)
    }

    private func enterFullScreen() {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
    }
}

private struct PreviewResizeControl: View {
    let onDecrease: () -> Void
    let onIncrease: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void
    @State private var isHovered = false

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.divider).frame(height: 2)
            HStack(spacing: 2) {
                resizeButton("chevron-up", label: "Reducir previsualización", action: onDecrease)
                Capsule().fill(Theme.muted.opacity(0.7)).frame(width: 32, height: 4)
                    .frame(width: 42, height: 22)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { onDragChanged($0.translation.height) }
                            .onEnded { _ in onDragEnded() }
                    )
                    .accessibilityLabel("Arrastrar para cambiar la altura de la previsualización")
                resizeButton("chevron-down", label: "Ampliar previsualización", action: onIncrease)
            }
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Theme.bg)
            .overlay { Rectangle().stroke(Theme.divider, lineWidth: 1) }
            .opacity(isHovered ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            let hovering: Bool
            switch phase {
            case .active: hovering = true
            case .ended: hovering = false
            }
            if hovering != isHovered {
                isHovered = hovering
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
        }
        .onDisappear { if isHovered { NSCursor.pop() } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ajustar tamaño de la previsualización")
    }

    private func resizeButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(name: icon, size: 12).frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private final class DraggingNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggingNSView { DraggingNSView() }
    func updateNSView(_ nsView: DraggingNSView, context: Context) {}
}

enum ExternalPlayer {
    private static func bundleID(for app: String) -> String {
        app == "VLC" ? "org.videolan.vlc" : "com.colliderli.iina"
    }

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
