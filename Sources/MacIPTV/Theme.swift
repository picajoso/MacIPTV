import AppKit
import CoreText
import SwiftUI

private enum AppResources {
    static let bundle: Bundle = {
        if let resources = Bundle.main.resourceURL,
           let packaged = Bundle(url: resources.appendingPathComponent("MacIPTV_MacIPTV.bundle")) {
            return packaged
        }
        return Bundle.module
    }()
}

enum Theme {
    private static func dynamic(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(red: CGFloat((value >> 16) & 0xff) / 255,
                           green: CGFloat((value >> 8) & 0xff) / 255,
                           blue: CGFloat(value & 0xff) / 255,
                           alpha: isDark ? darkAlpha : lightAlpha)
        })
    }

    static let bg = dynamic(0xF3F2F2, 0x1A1817)
    static let fg = dynamic(0x201E1D, 0xF3F2F2)
    static let surface = dynamic(0xEAE9E9, 0x24211F)
    static let divider = dynamic(0x201E1D, 0xF3F2F2, lightAlpha: 0.4, darkAlpha: 0.25)
    static let muted = dynamic(0x605D5D, 0xBDB9B8)
    static let faint = dynamic(0x7D7979, 0x8A8686)
    static let chip = dynamic(0xEAE7E7, 0x2D2B2B)
    static let chipFg = dynamic(0x444141, 0xD7D3D3)
    static let track = dynamic(0xD7D3D3, 0x3A3838)
    static let current = dynamic(0xFFF2EF, 0x3A1A14)
    static let hover = dynamic(0xEAE7E7, 0x2A2725)
    static let accentText = dynamic(0xAE1800, 0xFF9783)
    static let tile = dynamic(0xFFFFFF, 0x2D2B2B)
    static let selected = dynamic(0x201E1D, 0xF3F2F2)
    static let selectedFg = dynamic(0xF3F2F2, 0x1A1817)
    static let accent = dynamic(0xEC3013, 0xEC3013)
    static let accentPressed = dynamic(0xDD2B0F, 0xDD2B0F)
    static let accentOnDark = dynamic(0xFF9783, 0xFF9783)
    static let onRed = Color(red: 243/255, green: 242/255, blue: 242/255)
}

enum Archivo {
    static func register() {
        guard let url = AppResources.bundle.url(forResource: "Archivo", withExtension: "ttf", subdirectory: "Fonts") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Archivo", size: size).weight(weight)
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var title: String {
        switch self {
        case .system: "Sistema"
        case .light: "Claro"
        case .dark: "Oscuro"
        }
    }
    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct LucideIcon: View {
    let name: String
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let url = AppResources.bundle.url(forResource: name, withExtension: "pdf", subdirectory: "Icons"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
    }
}
