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
