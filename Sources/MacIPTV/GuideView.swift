import SwiftUI
import MacIPTVCore

/// Guia con filas de canales y columnas de tiempo alineadas (cabecera y
/// filas comparten el mismo scroll horizontal), al estilo TiviMate.
struct GuideView: View {
    let channels: [Channel]
    let guide: XMLTVGuide
    let onSelect: (Channel) -> Void

    @State private var windowStart = Calendar.current.dateInterval(of: .hour, for: Date())?.start ?? Date()
    @State private var now = Date()

    private let hourWidth: CGFloat = 150
    private let rowHeight: CGFloat = 44
    private let labelWidth: CGFloat = 190
    private let hours = 8

    private var trackWidth: CGFloat { CGFloat(hours) * hourWidth }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "HH:mm"
        return f
    }

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(channels) { channel in
                            row(for: channel)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(channel) }
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { date in now = date }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("Canal")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(width: labelWidth, alignment: .leading)
            ForEach(0..<hours, id: \.self) { hour in
                Text(timeFormatter.string(from: hourDate(hour)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: hourWidth, alignment: .leading)
            }
        }
        .frame(height: 24)
    }

    private func hourDate(_ hour: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: hour, to: windowStart) ?? windowStart
    }

    private func pixels(from date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(windowStart) / 60.0) * (hourWidth / 60.0)
    }

    private func row(for channel: Channel) -> some View {
        let tvg = channel.tvgID ?? ""
        let programmes = tvg.isEmpty ? [] : guide.programmes(for: tvg)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(channel.name)
                    .font(.callout)
                    .lineLimit(1)
                Text(channel.group)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(width: labelWidth, alignment: .leading)
            .frame(height: rowHeight)
            ZStack(alignment: .leading) {
                Color.clear
                ForEach(0..<hours, id: \.self) { hour in
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 1, height: rowHeight)
                        .offset(x: CGFloat(hour) * hourWidth)
                }
                ForEach(programmeBlocks(programmes), id: \.start) { block in
                    blockView(block)
                }
                let offset = pixels(from: now)
                if offset >= 0, offset <= trackWidth {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 1.5, height: rowHeight)
                        .offset(x: offset)
                }
            }
            .frame(width: trackWidth, height: rowHeight)
            .clipped()
        }
    }

    private struct Block: Hashable {
        var start: Date
        var end: Date
        var title: String
    }

    private func programmeBlocks(_ programmes: [Programme]) -> [Block] {
        let windowEnd = Calendar.current.date(byAdding: .hour, value: hours, to: windowStart) ?? windowStart
        var blocks: [Block] = []
        for p in programmes {
            let end = guide.effectiveEnd(of: p) ?? p.start.addingTimeInterval(30 * 60)
            if end <= windowStart || p.start >= windowEnd { continue }
            blocks.append(Block(start: max(p.start, windowStart),
                                end: min(end, windowEnd),
                                title: p.title))
        }
        return blocks
    }

    private func blockView(_ block: Block) -> some View {
        let x = pixels(from: block.start)
        let width = max(pixels(from: block.end) - x, 4)
        return Text(block.title)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .frame(width: max(width - 2, 4), height: rowHeight - 8, alignment: .leading)
            .background(Color.accentColor.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))
            .offset(x: x + 1)
    }
}
