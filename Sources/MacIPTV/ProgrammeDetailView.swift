import SwiftUI
import MacIPTVCore

struct ProgrammeDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let selection: ProgrammeSelection
    let guide: XMLTVGuide
    let onWatch: (Channel) -> Void

    private var channel: Channel { selection.channel }
    private var programme: Programme { selection.programme }
    private var end: Date { guide.effectiveEnd(of: programme) ?? programme.start.addingTimeInterval(1800) }
    private var isLive: Bool { programme.start <= Date() && Date() < end }
    private var isFuture: Bool { programme.start > Date() }
    private var isReminderSet: Bool {
        store.reminders.contains(store.reminderKey(channel: channel, programme: programme))
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.accent).frame(height: 4)
            HStack(spacing: 12) {
                ChannelLogo(channel: channel, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ChannelName(channel.name).title)
                        .font(Archivo.font(15, weight: .heavy))
                    Text("\(programme.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) · " +
                         "\(programme.start.formatted(date: .omitted, time: .shortened))–" +
                         "\(end.formatted(date: .omitted, time: .shortened))")
                        .font(Archivo.font(10)).tracking(1).foregroundStyle(Theme.accentText)
                }
                Spacer()
                Button { dismiss() } label: { LucideIcon(name: "x", size: 17) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cerrar ficha")
                    .help("Cerrar (Esc)")
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 2) }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    if isLive {
                        Text("DIRECTO").background(Theme.accent).foregroundStyle(.white)
                    } else if programme.start <= Date() {
                        Text("PASADO").background(Theme.selected).foregroundStyle(Theme.selectedFg)
                    } else {
                        Text("PRÓXIMAMENTE").background(Theme.chip).foregroundStyle(Theme.chipFg)
                    }
                    Text("\(Int(end.timeIntervalSince(programme.start) / 60)) min")
                        .background(Theme.chip).foregroundStyle(Theme.chipFg)
                }
                .font(Archivo.font(10))
                .padding(.vertical, 2)
                Text(programme.title)
                    .font(Archivo.font(24, weight: .heavy))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isLive {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let fraction = min(1, max(0, context.date.timeIntervalSince(programme.start) /
                                                   max(1, end.timeIntervalSince(programme.start))))
                        VStack(alignment: .leading, spacing: 5) {
                            GeometryReader { geometry in
                                Rectangle().fill(Theme.track)
                                    .overlay(alignment: .leading) {
                                        Rectangle().fill(Theme.accent).frame(width: geometry.size.width * fraction)
                                    }
                            }
                            .frame(height: 3)
                            Text("quedan \(Int(max(0, end.timeIntervalSince(context.date)) / 60)) min")
                                .font(Archivo.font(11.5)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                if let details = programme.details, !details.isEmpty {
                    Text(details)
                        .font(Archivo.font(14))
                        .foregroundStyle(Theme.muted)
                        .lineSpacing(6)
                }
                if isReminderSet {
                    Text("Recordatorio marcado para las \(programme.start.formatted(date: .omitted, time: .shortened)).")
                        .font(Archivo.font(12)).foregroundStyle(Theme.accentText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            HStack(spacing: 0) {
                Button {
                    if isFuture {
                        store.toggleReminder(channel: channel, programme: programme)
                    } else { dismiss() }
                } label: {
                    Text(isFuture ? (isReminderSet ? "Quitar aviso" : "Recordar") : "Cerrar")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                }
                .buttonStyle(.plain)
                Rectangle().fill(Theme.divider).frame(width: 1)
                Button {
                    onWatch(channel)
                    dismiss()
                } label: {
                    Text(isLive ? "Ver ahora" : "Ver canal")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .background(Theme.accent).foregroundStyle(.white)
            }
            .font(Archivo.font(13, weight: .semibold))
            .frame(height: 52)
            .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 2) }
        }
        .frame(width: 540)
        .background(Theme.bg)
        .foregroundStyle(Theme.fg)
    }
}
