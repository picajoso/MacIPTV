import SwiftUI
import AppKit
import MacIPTVCore

@main
struct MacIPTVApp: App {
    @State private var store = AppStore()

    init() { Archivo.register() }

    var body: some Scene {
        WindowGroup("MacIPTV") {
            ContentView()
                .environment(store)
                .environment(\.font, Archivo.font(13))
                .preferredColorScheme(store.appearance.colorScheme)
                .onChange(of: store.appearance) { _, value in value.apply() }
                .onAppear { store.appearance.apply() }
                .task { store.bootstrap(demo: CommandLine.arguments.contains("--demo")) }
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 720)
        .windowStyle(.hiddenTitleBar)
        Settings {
            SettingsView().environment(store)
                .preferredColorScheme(store.appearance.colorScheme)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Configurar fuente…") { store.showSettings = true }
                    .keyboardShortcut("n", modifiers: [.shift, .command])
                Button("Actualizar canales") { store.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Probar demo") { store.startDemo() }
                Button("Quitar fuente…") { store.confirmRemoveSource = true }
                    .disabled(store.activeSourceID == nil)
            }
            CommandGroup(after: .pasteboard) {
                Button("Buscar canales") { store.searchRequestID = UUID() }
                    .keyboardShortcut("f", modifiers: [.option, .command])
                Button("Copiar nombre del canal") {
                    if let channel = store.selectedChannel {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(channel.name, forType: .string)
                    }
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(store.selectedChannel == nil)
            }
            CommandMenu("Visualización") {
                Button("Directo") { store.tab = .live }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Guía") { store.tab = .guide }
                    .keyboardShortcut("2", modifiers: .command)
                Divider()
                Button(store.showGroups ? "Ocultar grupos" : "Mostrar grupos") { store.showGroups.toggle() }
                    .keyboardShortcut("s", modifiers: [.control, .command])
                Button(store.showChannels ? "Ocultar lista de canales" : "Mostrar lista de canales") {
                    store.showChannels.toggle()
                }
                .keyboardShortcut("l", modifiers: [.control, .command])
                Divider()
                Button("Pantalla completa") {
                    (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
                }.keyboardShortcut("f", modifiers: .command)
                Button(store.videoOnly ? "Salir de solo vídeo" : "Solo vídeo") {
                    store.tab = .live
                    store.videoOnly.toggle()
                }
                .keyboardShortcut("f", modifiers: [.shift, .command])
                Button("Rellenar en pantalla completa o solo vídeo") { store.fillVideo.toggle() }
                Divider()
                ForEach(AppearancePreference.allCases) { appearance in
                    Button((store.appearance == appearance ? "✓ " : "") + appearance.title) {
                        store.appearance = appearance
                    }
                }
            }
            CommandMenu("Canales") {
                Button("Canal siguiente") { store.moveSelection(by: 1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Button("Canal previo en la lista") { store.moveSelection(by: -1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("Volver al canal anterior") { store.returnToPreviousChannel() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                    .disabled(store.previousChannelID == nil)
                Button(store.selectedChannelID.map { store.favorites.contains($0) } == true
                       ? "Quitar de Favoritos" : "Añadir a Favoritos") {
                    if let id = store.selectedChannelID { store.toggleFavorite(id) }
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(store.selectedChannelID == nil)
                Divider()
                Button("Abrir en VLC") { store.externalRequestApp = "VLC" }
                    .disabled(store.selectedChannelID == nil || !ExternalPlayer.isInstalled("VLC"))
                Button("Abrir en IINA") { store.externalRequestApp = "IINA" }
                    .disabled(store.selectedChannelID == nil || !ExternalPlayer.isInstalled("IINA"))
            }
            CommandGroup(after: .help) {
                Button("Abrir diagnóstico") { NSWorkspace.shared.open(DiagnosticLog.fileURL) }
            }
        }
    }
}
