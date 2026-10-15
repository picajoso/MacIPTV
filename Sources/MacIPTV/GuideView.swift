import SwiftUI
import MacIPTVCore

private struct GuideScrollOffset: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct GuideView: View {
    @Environment(AppStore.self) private var store
    let channels: [Channel]
    let guide: XMLTVGuide
    let onSelect: (Channel) -> Void

    @State private var dayOffset = 0
    @State private var horizontalOffset: CGFloat = 0
    @State private var verticalOffset: CGFloat = 0
    @State private var selectedProgramme: ProgrammeSelection?
    @State private var now = Date()

    private let minutesPerDay = 18 * 60
    private let pointsPerMinute: CGFloat = 4
    private let labelWidth: CGFloat = 190
    private let rowHeight: CGFloat = 58
    private let hourHeaderHeight: CGFloat = 30
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var trackWidth: CGFloat { CGFloat(minutesPerDay) * pointsPerMinute }
    private var day: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }
    private var dayStart: Date {
        Calendar.current.date(byAdding: .hour, value: 6,
                              to: Calendar.current.startOfDay(for: day)) ?? day
    }
    private var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1,
                              to: Calendar.current.startOfDay(for: day)) ?? dayStart.addingTimeInterval(18 * 3600)
    }

    var body: some View {
        VStack(spacing: 0) {
            dayBar
            GeometryReader { viewport in
                ZStack(alignment: .topLeading) {
                    ScrollViewReader { proxy in
                        ScrollView([.horizontal, .vertical]) {
                            LazyVStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    ForEach(0..<36, id: \.self) { halfHour in
                                        Color.clear.frame(width: 120, height: hourHeaderHeight)
                                            .id("hour-\(halfHour)")
                                    }
                                }
                                ForEach(channels) { channel in row(channel) }
                            }
                            .frame(width: trackWidth, alignment: .leading)
                            .frame(minHeight: viewport.size.height, alignment: .top)
                            .background(GeometryReader { geometry in
                                let origin = geometry.frame(in: .named("guideScroll")).origin
                                Color.clear.preference(key: GuideScrollOffset.self,
                                                       value: CGSize(width: max(0, -origin.x),
                                                                     height: max(0, -origin.y)))
                            })
                        }
                        .coordinateSpace(name: "guideScroll")
                        .onPreferenceChange(GuideScrollOffset.self) { offset in
                            horizontalOffset = offset.width
                            verticalOffset = offset.height
                        }
                        .onAppear { scrollToInitial(proxy) }
                        .onChange(of: dayOffset) { _, _ in scrollToInitial(proxy) }
                    }
                    VStack(spacing: 0) {
                        Color.clear.frame(height: hourHeaderHeight)
                        ForEach(channels) { channel in channelLabel(channel) }
                    }
                    .offset(y: -verticalOffset)
                    .frame(width: labelWidth, height: viewport.size.height, alignment: .topLeading)
                    .clipped()
                    hourHeader
                        .frame(width: viewport.size.width, height: hourHeaderHeight, alignment: .leading)
                        .clipped()
                    Theme.bg.frame(width: labelWidth, height: hourHeaderHeight)
                        .overlay(alignment: .trailing) { Rectangle().fill(Theme.divider).frame(width: 2) }
                }
            }
        }
        .background(Theme.bg)
        .onReceive(timer) { now = $0 }
        .sheet(item: $selectedProgramme) { selection in
            ProgrammeDetailView(selection: selection, guide: guide) { channel in
                onSelect(channel)
            }
            .environment(store)
        }
    }

    private var availableDays: [Int] {
        (-1...3).filter { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
            let start = Calendar.current.startOfDay(for: date)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
            return channels.contains { channel in
                guard let id = channel.tvgID else { return false }
                return guide.programmes(for: id).contains { programme in
                    programme.start < end && (guide.effectiveEnd(of: programme) ?? programme.start) > start
                }
            }
        }
    }

    private var dayBar: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(channels.filter { $0.tvgID != nil }.count) canales con guía · \(Date(), format: .dateTime.weekday(.abbreviated).day())")
                    .font(Archivo.font(10)).tracking(1).foregroundStyle(Theme.accentText)
                Text(groupTitle).font(Archivo.font(19, weight: .heavy)).lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(availableDays, id: \.self) { offset in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { dayOffset = offset }
                } label: {
                    let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dayTitle(offset, date: date))
                            .font(Archivo.font(13, weight: offset == dayOffset ? .heavy : .semibold))
                        Text(date, format: .dateTime.day().month(.abbreviated))
                            .font(Archivo.font(10.5)).opacity(0.75)
                    }
                    .padding(.horizontal, 10)
                    .frame(width: 92, height: 62, alignment: .leading)
                    .background(offset == dayOffset ? Theme.accent : Theme.bg)
                    .foregroundStyle(offset == dayOffset ? Theme.onRed : Theme.fg)
                }
                .buttonStyle(.plain)
            }
            Rectangle().fill(Theme.divider).frame(width: 2, height: 62)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { dayOffset = 0 }
            } label: {
                HStack(spacing: 5) { LucideIcon(name: "clock", size: 16); Text("Ahora") }
                    .font(Archivo.font(13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 62)
            }
            .buttonStyle(.plain)
            .help("Ir a la hora actual")
        }
        .frame(height: 62)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 2) }
    }

    private var groupTitle: String {
        switch store.selectedGroup {
        case "__todos", nil: "Todos los canales"
        case "__favoritos": "Favoritos"
        case "__recientes": "Recientes"
        case .some(let name): name
        }
    }

    private func dayTitle(_ offset: Int, date: Date) -> String {
        switch offset {
        case -1: "Ayer"
        case 0: "Hoy"
        case 1: "Mañana"
        default: date.formatted(.dateTime.weekday(.wide)).capitalized
        }
    }

    private var hourHeader: some View {
        HStack(spacing: 0) {
            ForEach(0..<36, id: \.self) { halfHour in
                let date = dayStart.addingTimeInterval(TimeInterval(halfHour * 30 * 60))
                Text(date, format: .dateTime.hour().minute())
                    .font(Archivo.font(11))
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 6)
                    .frame(width: 120, height: hourHeaderHeight, alignment: .leading)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Theme.divider).frame(width: 1)
                    }
            }
        }
        .offset(x: -horizontalOffset)
        .frame(width: trackWidth, alignment: .leading)
        .frame(height: hourHeaderHeight)
        .background(Theme.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 2) }
    }

    private func channelLabel(_ channel: Channel) -> some View {
        Button { onSelect(channel) } label: {
            HStack(spacing: 9) {
                ChannelLogo(channel: channel, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ChannelName(channel.name).title)
                        .font(Archivo.font(12.5, weight: .heavy)).lineLimit(1)
                    Text(ChannelName(channel.name).tags.joined(separator: " · "))
                        .font(Archivo.font(10)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(width: labelWidth, height: rowHeight)
            .background(store.selectedChannelID == channel.id ? Theme.current : Theme.bg)
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.divider).frame(width: 2) }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }

    private func row(_ channel: Channel) -> some View {
            ZStack(alignment: .topLeading) {
                Theme.bg
                ForEach(0..<36, id: \.self) { halfHour in
                    Rectangle().fill(Theme.divider).frame(width: 1, height: rowHeight)
                        .offset(x: CGFloat(halfHour) * 120)
                }
                if let tvgID = channel.tvgID {
                    ForEach(guide.programmes(for: tvgID).filter { programme in
                        let end = guide.effectiveEnd(of: programme) ?? programme.start.addingTimeInterval(1800)
                        return programme.start < dayEnd && end > dayStart
                    }, id: \.start) { programme in
                        programmeBlock(programme, channel: channel)
                    }
                }
                if dayOffset == 0 {
                    Rectangle().fill(Theme.accent).frame(width: 2, height: rowHeight)
                        .offset(x: CGFloat(now.timeIntervalSince(dayStart) / 60) * pointsPerMinute)
                }
            }
            .frame(width: trackWidth, height: rowHeight)
            .clipped()
        .frame(height: rowHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    private func programmeBlock(_ programme: Programme, channel: Channel) -> some View {
        let end = guide.effectiveEnd(of: programme) ?? programme.start.addingTimeInterval(1800)
        let clippedStart = max(programme.start, dayStart)
        let clippedEnd = min(end, dayEnd)
        let x = CGFloat(clippedStart.timeIntervalSince(dayStart) / 60) * pointsPerMinute
        let width = max(2, CGFloat(clippedEnd.timeIntervalSince(clippedStart) / 60) * pointsPerMinute)
        let live = programme.start <= now && now < end
        let past = end <= now
        return Button {
            selectedProgramme = ProgrammeSelection(channel: channel, programme: programme)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                if width >= 80 {
                    HStack(spacing: 5) {
                        Text(programme.start, format: .dateTime.hour().minute())
                        Text("–")
                        Text(end, format: .dateTime.hour().minute())
                        if live { Text("DIRECTO").foregroundStyle(Theme.accentText) }
                        if store.reminders.contains(store.reminderKey(channel: channel, programme: programme)) {
                            LucideIcon(name: "bell-ring", size: 12).foregroundStyle(Theme.accentText)
                        }
                    }
                    .font(Archivo.font(10.5))
                }
                Text(programme.title)
                    .font(Archivo.font(12.5, weight: live ? .heavy : .semibold))
                    .lineLimit(2)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .frame(width: width, height: rowHeight, alignment: .topLeading)
            .background(live ? Theme.current : Theme.bg)
            .foregroundStyle(past ? Theme.faint : Theme.fg)
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.divider).frame(width: 1) }
            .overlay(alignment: .bottom) {
                if live {
                    Rectangle().fill(Theme.accent)
                        .frame(width: width * min(1, max(0, now.timeIntervalSince(programme.start) /
                                                          max(1, end.timeIntervalSince(programme.start)))),
                               height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .offset(x: x)
        .accessibilityLabel("\(programme.title), \(programme.start.formatted(date: .omitted, time: .shortened))")
    }

    private func scrollToInitial(_ proxy: ScrollViewProxy) {
        let minutes = dayOffset == 0
            ? Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current.component(.minute, from: Date()) - 360
            : 19 * 60 + 30 - 360
        let index = max(0, min(35, (minutes - 45) / 30))
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo("hour-\(index)", anchor: .leading)
            }
        }
    }
}

struct ProgrammeSelection: Identifiable {
    let channel: Channel
    let programme: Programme
    var id: String { channel.id + "|" + String(programme.start.timeIntervalSince1970) }
}
