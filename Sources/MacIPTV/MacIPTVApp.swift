import SwiftUI
import AppKit

@main
struct MacIPTVApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup("MacIPTV") {
            ContentView()
                .environment(store)
                .task { store.bootstrap(demo: CommandLine.arguments.contains("--demo")) }
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1200, height: 760)
        .commands {
            CommandMenu("Canales") {
                Button("Canal siguiente") { store.moveSelection(by: 1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Button("Canal previo en la lista") { store.moveSelection(by: -1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("Volver al canal anterior") { store.returnToPreviousChannel() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                    .disabled(store.previousChannelID == nil)
            }
            CommandGroup(after: .newItem) {
                Button("Fuente del proveedor...") { store.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
                Button("Actualizar canales") { store.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Pantalla completa") {
                    (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                .help("Alterna la pantalla completa de la ventana")
            }
        }
    }
}
