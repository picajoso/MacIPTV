import Foundation
import MacIPTVCore

/// Contenido sintetico claramente etiquetado, con el HLS publico de Apple.
enum DemoContent {
    static let playlistText = """
    #EXTM3U
    #EXTINF:-1 tvg-id="demo.nature" group-title="Demostración" tvg-name="Naturaleza · Demo",Naturaleza · Demo
    https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8
    #EXTINF:-1 tvg-id="demo.news" group-title="Demostración" tvg-name="Noticias · Demo",Noticias · Demo
    https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8
    #EXTINF:-1 tvg-id="demo.cinema" group-title="Cine de prueba" tvg-name="Cine · Demo",Cine · Demo
    https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8
    """

    /// Programacion ficticia: bloques de 45 minutos alrededor de ahora.
    static func makeGuide() -> XMLTVGuide {
        let names = ["Reportajes de demostración", "Informativo ficticio", "Pelicula de prueba",
                     "Documental simulado", "Cartelera inventada", "Series de ejemplo"]
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let anchor = cal.date(bySetting: .minute, value: 0, of: now)!
        var dict: [String: [Programme]] = [:]
        for tvg in ["demo.nature", "demo.news", "demo.cinema"] {
            var list: [Programme] = []
            for offset in -8...12 {
                guard let start = cal.date(byAdding: .minute, value: offset * 45, to: anchor) else { continue }
                let end = cal.date(byAdding: .minute, value: 45, to: start)
                let title = names[abs(offset) % names.count] + " · demo"
                list.append(Programme(channelID: tvg, title: title, details: "Programacion ficticia de demostracion.",
                                      start: start, end: end))
            }
            dict[tvg] = list
        }
        return XMLTVGuide(programmes: dict)
    }
}
