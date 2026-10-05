import Foundation

func require(_ value: Bool, _ label: String) throws {
    guard value else { throw NSError(domain: "ImportSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
    print("PASS: " + label)
}

Task {
    do {
        let importer = SourceImporter()
        let valid = try await importer.importSource(.m3uURL(url: "http://127.0.0.1:18768/playlist.m3u", xmltvURL: "http://127.0.0.1:18768/guide.xml"))
        try require(valid.channels.count == 3, "M3U imports three channels")
        try require(valid.channels[0].name == "Naturaleza · Demo", "channel name preserved")
        try require(valid.guide?.nowPlaying(channelID: "demo.nature", at: Date()) != nil, "XMLTV current programme matches channel ID")
        let xtream = try await importer.importSource(.xtream(baseURL: "http://127.0.0.1:18768", username: "fixture", password: "fixture"))
        try require(xtream.channels.count == 3, "Xtream endpoint import works")
        do {
            _ = try await importer.importSource(.m3uURL(url: "http://127.0.0.1:18768/empty.m3u", xmltvURL: nil))
            try require(false, "empty M3U must fail")
        } catch IPTVError.emptyPlaylist { print("PASS: empty M3U rejected") }
        let partial = try await importer.importSource(.m3uURL(url: "http://127.0.0.1:18768/playlist.m3u", xmltvURL: "http://127.0.0.1:18768/invalid.xml"))
        try require(partial.channels.count == 3 && partial.guideWarning != nil, "bad optional XMLTV keeps usable channels and warning")
        do {
            _ = try await importer.importSource(.m3uURL(url: "http://127.0.0.1:18768/unavailable?token=fixture-secret", xmltvURL: nil))
            try require(false, "HTTP failure must throw")
        } catch let error as IPTVError {
            try require(!error.localizedDescription.contains("fixture-secret"), "HTTP error hides URL token")
        }
        print("PASS: provider fixture smoke test")
        exit(0)
    } catch {
        print("FAIL: " + error.localizedDescription)
        exit(1)
    }
}
RunLoop.main.run()
