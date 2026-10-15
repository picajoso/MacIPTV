import SwiftUI
import AppKit
import MacIPTVCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var section: Section = .sources
    @State private var sourceToRemove: UUID?

    private enum Section: String, CaseIterable {
        case sources = "Fuentes", playback = "Reproducción", appearance = "Apariencia", advanced = "Avanzado"
        var icon: String {
            switch self {
            case .sources: "list"
            case .playback: "play"
            case .appearance: "monitor"
            case .advanced: "settings"
            }
        }
    }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Section.allCases, id: \.self) { item in
                    Button { section = item } label: {
                        VStack(spacing: 4) {
                            LucideIcon(name: item.icon, size: 18)
                            Text(item.rawValue).font(Archivo.font(12.5, weight: section == item ? .heavy : .semibold))
                        }
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .foregroundStyle(section == item ? Theme.accentText : Theme.muted)
                        .background(section == item ? Theme.bg : Theme.surface)
                    }.buttonStyle(.plain)
                }
            }
            Rectangle().fill(Theme.divider).frame(height: 1)
            Group {
                switch section {
                case .sources: sources
                case .playback: playback
                case .appearance: appearance
                case .advanced: advanced
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .frame(width: 640, height: 460)
        .background(Theme.bg).foregroundStyle(Theme.fg)
        .sheet(isPresented: Binding(
            get: { sourceToRemove != nil }, set: { if !$0 { sourceToRemove = nil } }
        )) {
            ConfirmationSheet(title: "Quitar fuente",
                              message: "La fuente se quitará del Llavero. Los demás proveedores permanecerán guardados.",
                              actionTitle: "Quitar fuente") {
                if let sourceToRemove { store.removeSource(sourceToRemove) }
                sourceToRemove = nil
            }
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Fuentes", subtitle: "Selecciona un proveedor o añade otro.")
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.savedSources.keys.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { id in
                        if let saved = store.savedSources[id] { sourceRow(id, saved: saved) }
                    }
                    if store.savedSources.isEmpty {
                        Text("Aún no hay fuentes guardadas.")
                            .font(Archivo.font(13)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
            }
            Spacer(minLength: 10)
            HStack(spacing: 10) {
                Button("Añadir fuente…") { store.showSettings = true }
                    .settingsPrimary()
                Button("Probar demo") { store.startDemo() }
                    .settingsSecondary()
            }
        }
    }

    private func sourceRow(_ id: UUID, saved: SavedSource) -> some View {
        HStack(spacing: 8) {
            Button { store.activateSource(id) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(saved.source.summary).font(Archivo.font(14.5, weight: .heavy)).lineLimit(1)
                        if id == store.activeSourceID {
                            Text("ACTIVA").font(Archivo.font(9, weight: .heavy)).tracking(0.8)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Theme.accent).foregroundStyle(Theme.onRed)
                        }
                    }
                    Text("\(store.channelCount(for: id)) canales · " +
                         (store.updatedAt(for: id)?.formatted(date: .abbreviated, time: .shortened) ?? "Sin actualizar"))
                        .font(Archivo.font(11)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Button { store.activateSource(id) } label: { LucideIcon(name: "refresh-cw", size: 16) }
                .help("Actualizar fuente")
            Button { sourceToRemove = id } label: { LucideIcon(name: "x", size: 16) }
                .help("Quitar fuente")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14).frame(height: 67)
        .background(Theme.surface)
        .overlay { Rectangle().stroke(Theme.divider, lineWidth: 1) }
    }

    private var playback: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 24) {
            heading("Reproducción", subtitle: "Elige cómo empieza y se muestra el vídeo.")
            settingsRow("Al abrir la app", help: "Selecciona si quieres reanudar el último canal.") {
                choices([("Reanudar último canal", true), ("No reproducir", false)], selection: $store.resumeLastChannel)
            }
            settingsRow("Imagen en pantalla completa", help: "La previsualización siempre conserva el fotograma completo. Rellenar recorta los bordes en pantalla completa.") {
                choices([("Ajustar", false), ("Rellenar", true)], selection: $store.fillVideo)
            }
            settingsRow("Reproductor externo", help: "Se usa al abrir un canal fuera de MacIPTV.") {
                choices([("VLC", "VLC"), ("IINA", "IINA")], selection: $store.externalPlayer)
            }
            settingsRow("Ocultar controles", help: "Con VoiceOver permanecen siempre visibles.") {
                choices([("3 s", 3), ("5 s", 5), ("Nunca", 0)], selection: $store.hideControlsAfter)
            }
        }
    }

    private var appearance: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 24) {
            heading("Apariencia", subtitle: "Elige el aspecto de la interfaz.")
            settingsRow("Tema", help: "Sistema sigue el ajuste de macOS.") {
                choices(AppearancePreference.allCases.map { ($0.title, $0) }, selection: $store.appearance)
            }
        }
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Avanzado", subtitle: "Herramientas para revisar problemas de reproducción.")
            Text("El diagnóstico registra eventos técnicos sin incluir contraseñas ni direcciones completas de canales.")
                .font(Archivo.font(13)).foregroundStyle(Theme.muted)
            Button("Abrir diagnóstico") { NSWorkspace.shared.open(DiagnosticLog.fileURL) }
                .settingsSecondary()
        }
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(Archivo.font(22, weight: .heavy))
            Text(subtitle).font(Archivo.font(12.5)).foregroundStyle(Theme.muted)
        }.padding(.bottom, 18)
    }

    private func settingsRow<Content: View>(_ title: String, help: String,
                                            @ViewBuilder control: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Archivo.font(13.5, weight: .heavy))
                Text(help).font(Archivo.font(11)).foregroundStyle(Theme.muted)
            }.frame(width: 200, alignment: .leading)
            control()
        }
    }

    private func choices<Value: Hashable>(_ options: [(String, Value)], selection: Binding<Value>) -> some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button { selection.wrappedValue = option.1 } label: {
                    Text(option.0).font(Archivo.font(11.5, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(selection.wrappedValue == option.1 ? Theme.accent : Theme.surface)
                        .foregroundStyle(selection.wrappedValue == option.1 ? Theme.onRed : Theme.fg)
                }.buttonStyle(.plain)
            }
        }
        .overlay { Rectangle().stroke(Theme.divider, lineWidth: 1) }
    }
}

private extension View {
    func settingsPrimary() -> some View {
        self.buttonStyle(.plain).font(Archivo.font(12.5, weight: .heavy))
            .padding(.horizontal, 16).frame(height: 36)
            .background(Theme.accent).foregroundStyle(Theme.onRed)
    }
    func settingsSecondary() -> some View {
        self.buttonStyle(.plain).font(Archivo.font(12.5, weight: .heavy))
            .padding(.horizontal, 16).frame(height: 36)
            .background(Theme.surface)
            .overlay { Rectangle().stroke(Theme.divider, lineWidth: 1) }
    }
}
