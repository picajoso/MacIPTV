import Foundation

struct ChannelName: Equatable {
    let title: String
    let tags: [String]

    init(_ raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var extracted: [String] = []
        while value.hasPrefix("|") {
            let rest = value.dropFirst()
            guard let close = rest.firstIndex(of: "|") else { break }
            let tag = String(rest[..<close]).uppercased()
            guard ["ES", "EN", "UK", "FR", "DE", "IT", "PT"].contains(tag) else { break }
            extracted.append(tag)
            value = String(rest[rest.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        let quality = ["FHD", "UHD", "4K", "HD", "SD"].first { value.uppercased().hasSuffix(" " + $0) }
        if let quality {
            value = String(value.dropLast(quality.count)).trimmingCharacters(in: .whitespaces)
            extracted.append(quality)
        }
        if value == value.uppercased() {
            value = value.split(separator: " ").map { word in
                word.count <= 3 ? String(word) :
                    String(word.prefix(1)).uppercased() + String(word.dropFirst()).lowercased()
            }.joined(separator: " ")
        }
        title = value.isEmpty ? raw : value
        tags = extracted
    }
}
