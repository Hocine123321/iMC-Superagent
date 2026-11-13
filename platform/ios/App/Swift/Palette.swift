import SwiftUI
import UIKit

/// iMC's colours: a blue and a red, each tuned for dark and light, over a deep navy-to-wine ground.
/// Everything is dynamic, so one switch (Settings > Look > Appearance) turns the whole launcher.
private func dyn(_ dark: UInt32, _ light: UInt32) -> Color {
    Color(uiColor: UIColor { trait in
        let v = trait.userInterfaceStyle == .light ? light : dark
        return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    })
}

enum Palette {
    static let blue = dyn(0x5B9BFF, 0x1E5FE6)
    static let red = dyn(0xFF5A66, 0xD1283C)
    /// The deep ends of the two, for gradients on tiles and the app mark.
    static let blueDeep = dyn(0x2F63D8, 0x1747B8)
    static let redDeep = dyn(0xD8283C, 0xA3182A)
    /// The ground behind everything: navy at the top, wine at the bottom.
    static let ink = dyn(0x070B1C, 0xF2F5FD)
    static let wine = dyn(0x1B0A14, 0xFCF1F4)
    /// Results of a check. Green is for "fine" only; the rest of the app stays blue and red.
    static let ok = dyn(0x4ADE80, 0x15803D)
    static let warn = dyn(0xFBBF24, 0xB45309)
}

// The two brand colours as the environment sees them, so a change of accent in Settings repaints everything.
private struct BrandKey: EnvironmentKey { static let defaultValue: Color = Palette.blue }
private struct Brand2Key: EnvironmentKey { static let defaultValue: Color = Palette.red }

extension EnvironmentValues {
    /// The accent colour (blue unless Settings says red).
    var brand: Color { get { self[BrandKey.self] } set { self[BrandKey.self] = newValue } }
    /// The other one of the pair.
    var brand2: Color { get { self[Brand2Key.self] } set { self[Brand2Key.self] = newValue } }
}

// MARK: - Colours the person picks

extension Palette {
    private static func hsb(_ hex: UInt32) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        let c = UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b)
    }

    /// The colour as the person picked it, for swatches and colour pickers.
    static func plain(hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// A picked colour tuned for each appearance, the way the built-in blue and red are: lifted to stay readable on the
    /// dark ground, deepened to stay readable on the light one. Hue never moves.
    static func dynamic(hex: UInt32) -> Color {
        let (h, s, b) = hsb(hex)
        return Color(uiColor: UIColor { trait in
            if trait.userInterfaceStyle == .light {
                return UIColor(hue: h, saturation: min(1, s * 1.3), brightness: min(b, 0.92) * 0.9, alpha: 1)
            }
            return UIColor(hue: h, saturation: s, brightness: max(b, 0.78), alpha: 1)
        })
    }

    /// The deep end of a picked colour, for the gradient on icon tiles.
    static func deep(hex: UInt32) -> Color {
        let (h, s, b) = hsb(hex)
        return Color(uiColor: UIColor { trait in
            let light = trait.userInterfaceStyle == .light
            return UIColor(hue: h, saturation: min(1, s * 1.15 + 0.05), brightness: (light ? min(b, 0.92) * 0.9 : max(b, 0.78)) * 0.62, alpha: 1)
        })
    }

    /// RRGGBB text for the file, and back.
    static func hexString(_ hex: UInt32) -> String { String(format: "%06X", hex & 0xFFFFFF) }
    static func hex(from text: String?) -> UInt32? {
        guard let t = text?.trimmingCharacters(in: .whitespaces), t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        return v
    }
    static func hex(from colour: Color) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(colour).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return (byte(r) << 16) | (byte(g) << 8) | byte(b)
    }
}

/// A named pair of colours and how they mix behind the launcher.
struct ThemePreset: Identifiable, Equatable {
    let id: String
    let name: String
    let first: UInt32
    let second: UInt32
    let balance: Double

    /// The default is the first: blue with a little red.
    static let all: [ThemePreset] = [
        ThemePreset(id: "blue-red", name: "Blue and red", first: 0x5B9BFF, second: 0xFF5A66, balance: 0.30),
        ThemePreset(id: "red-blue", name: "Red and blue", first: 0xFF5A66, second: 0x5B9BFF, balance: 0.30),
        ThemePreset(id: "ocean", name: "Ocean", first: 0x38BDF8, second: 0x2DD4BF, balance: 0.35),
        ThemePreset(id: "sunset", name: "Sunset", first: 0xFF8A3D, second: 0xFF4D8D, balance: 0.45),
        ThemePreset(id: "forest", name: "Forest", first: 0x4ADE80, second: 0xE3C541, balance: 0.30),
        ThemePreset(id: "violet", name: "Violet", first: 0xA78BFA, second: 0x60A5FA, balance: 0.40),
        ThemePreset(id: "ember", name: "Ember", first: 0xFF5A4D, second: 0xFFA23D, balance: 0.35),
        ThemePreset(id: "mint", name: "Mint", first: 0x2DD4BF, second: 0x818CF8, balance: 0.35),
        ThemePreset(id: "slate", name: "Slate", first: 0x94A3B8, second: 0x64748B, balance: 0.30),
    ]
    static let standard = all[0]
}

private struct BrandDeepKey: EnvironmentKey { static let defaultValue: Color = Palette.blueDeep }
private struct Brand2DeepKey: EnvironmentKey { static let defaultValue: Color = Palette.redDeep }
private struct LightweightKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// The deep end of the first colour and of the second (icon tiles).
    var brandDeep: Color { get { self[BrandDeepKey.self] } set { self[BrandDeepKey.self] = newValue } }
    var brand2Deep: Color { get { self[Brand2DeepKey.self] } set { self[Brand2DeepKey.self] = newValue } }
    /// Lightweight visuals: the repeated and large Liquid Glass surfaces are drawn as plain tinted ones instead.
    var lightweight: Bool { get { self[LightweightKey.self] } set { self[LightweightKey.self] = newValue } }
}
