import SwiftUI
import MacIPTVCore

struct ChannelListView: View {
    @Environment(AppStore.self) private var store
    var onExternal: (Channel, String) -> Void = { _, _ in }
    var onFullScreen: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(groupTitle).font(Archivo.font(16, weight: .heavy)).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(store.visibleChannels.count) canales")
                    .font(Archivo.font(11)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 2) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.visibleChannels) { channel in
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            row(channel, at: context.date)
                        }
                    }
                }
            }
            .overlay {
                if store.visibleChannels.isEmpty { emptyState }
            }
        }
        .background(Theme.bg)
        .onMoveCommand { direction in
            switch direction {
            case .up: store.moveSelection(by: -1)
            case .down: store.moveSelection(by: 1)
            default: break
            }
        }
    }

    private var groupTitle: String {
        switch store.selectedGroup {
        case "__todos", nil: "Todos los canales"
        case "__favoritos": "Favoritos"
        case "__recientes": "Recientes"
        case .some(let name): name
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.hasChannels ? "Nada que mostrar" : "Sin canales")
                .font(Archivo.font(16, weight: .heavy))
            Text(store.hasChannels ? "Prueba otra búsqueda o grupo." : "Conecta un proveedor o prueba la demo.")
                .font(Archivo.font(12.5)).foregroundStyle(Theme.muted)
            if !store.hasChannels {
                Button("Probar demo") { store.startDemo() }
                    .buttonStyle(.plain).padding(8).background(Theme.accent).foregroundStyle(.white)
                Button("Conectar proveedor") { store.showSettings = true }
                    .buttonStyle(.plain).foregroundStyle(Theme.accentText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ channel: Channel, at date: Date) -> some View {
        let name = ChannelName(channel.name)
        let current = store.selectedChannelID == channel.id
        let programme = store.nowPlaying(channel, at: date)
        let end = programme.flatMap { store.guide?.effectiveEnd(of: $0) }
        let fraction: Double = if let programme, let end, end > programme.start {
            min(1, max(0, date.timeIntervalSince(programme.start) / end.timeIntervalSince(programme.start)))
        } else { 0 }
        return HStack(spacing: 12) {
            Button { store.selectedChannelID = channel.id } label: {
                HStack(spacing: 12) {
                    ChannelLogo(channel: channel, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(name.title).font(Archivo.font(13.5, weight: .heavy)).lineLimit(1)
                    if let quality = name.tags.first(where: { ["FHD", "UHD", "4K", "HD", "SD"].contains($0) }) {
                        Text(quality).font(Archivo.font(9)).tracking(0.5)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Theme.chip).foregroundStyle(Theme.chipFg)
                    }
                    if current { LucideIcon(name: "audio-lines", size: 13).foregroundStyle(Theme.accent) }
                }
                Text(programme?.title ?? "Sin programación")
                    .font(Archivo.font(11.5)).lineLimit(1)
                HStack(spacing: 8) {
                    GeometryReader { g in
                        Rectangle().fill(Theme.track)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Theme.accent).frame(width: g.size.width * fraction)
                            }
                    }
                    .frame(height: 2)
                    if let end {
                        Text(end, format: .dateTime.hour().minute())
                            .font(Archivo.font(10)).foregroundStyle(Theme.muted)
                    }
                }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ver canal \(name.title)")
            .help("Reproducir \(name.title); doble clic para pantalla completa")
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                store.selectedChannelID = channel.id
                onFullScreen()
            })
            Button { store.toggleFavorite(channel.id) } label: {
                LucideIcon(name: "heart", size: 16)
                    .foregroundStyle(store.favorites.contains(channel.id) ? Theme.accent : Theme.faint)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.favorites.contains(channel.id) ? "Quitar de favoritos" : "Añadir a favoritos")
            .help("Favorito (⌘D)")
        }
        .padding(.leading, 14).padding(.trailing, 6)
        .frame(height: 62)
        .background(current ? Theme.current : Theme.bg)
        .contentShape(Rectangle())
        .contextMenu {
            Button(store.favorites.contains(channel.id) ? "Quitar de favoritos" : "Añadir a favoritos") {
                store.toggleFavorite(channel.id)
            }
            if store.favorites.contains(channel.id) {
                Button("Subir favorito") { store.moveFavorite(channel.id, by: -1) }
                Button("Bajar favorito") { store.moveFavorite(channel.id, by: 1) }
            }
            Divider()
            Button("Abrir en VLC") { onExternal(channel, "VLC") }
                .disabled(!ExternalPlayer.isInstalled("VLC"))
            Button("Abrir en IINA") { onExternal(channel, "IINA") }
                .disabled(!ExternalPlayer.isInstalled("IINA"))
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

struct ChannelLogo: View {
    let channel: Channel
    let size: CGFloat

    var body: some View {
        ZStack {
            Theme.tile
            if let raw = channel.logoURL, let url = URL(string: raw) {
                AsyncImage(url: url) { image in image.resizable().scaledToFit().padding(3) }
                    placeholder: { initials }
            } else { initials }
        }
        .frame(width: size, height: size)
        .overlay { Rectangle().stroke(Theme.divider, lineWidth: 1) }
    }

    private var initials: some View {
        Text(ChannelName(channel.name).title.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
            .font(Archivo.font(size * 0.26, weight: .heavy))
            .foregroundStyle(Theme.fg)
    }
}
