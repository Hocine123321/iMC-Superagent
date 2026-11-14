import SwiftUI
import UIKit

/// The home screen icon follows the colour theme, or is picked by hand (Settings > Look > App icon): each preset has an icon of its own (the dirt block lit in that
/// preset's two colours; tools/make_app_icon.py draws them, project.yml lists them). A pair of colours that is not a
/// preset gets the icon of the nearest preset. iOS only allows icons that are in the app, so a free colour pair cannot
/// have an icon of its own.
///
/// iOS shows a short system notice ("You have changed the icon for ...") every time the icon changes; that notice cannot be
/// turned off by an app. So the icon is changed once, a moment after the last colour change (a colour picker being dragged
/// changes the colour many times a second), and only if it would actually be a different icon.
enum AppIconTheme {
    /// The asset name of the preset's icon; nil is the app's own icon (the first preset).
    static func iconName(for preset: ThemePreset) -> String? {
        preset.id == ThemePreset.standard.id ? nil : "AppIcon-" + preset.id
    }

    static func nearest(_ colour1: UInt32, _ colour2: UInt32) -> ThemePreset {
        func distance(_ a: UInt32, _ b: UInt32) -> Double {
            func channel(_ v: UInt32, _ shift: UInt32) -> Double { Double((v >> shift) & 0xFF) }
            let dr = channel(a, 16) - channel(b, 16), dg = channel(a, 8) - channel(b, 8), db = channel(a, 0) - channel(b, 0)
            return dr * dr + dg * dg + db * db
        }
        return ThemePreset.all.min { distance(colour1, $0.first) + distance(colour2, $0.second) < distance(colour1, $1.first) + distance(colour2, $1.second) } ?? ThemePreset.standard
    }

    private static var pending: DispatchWorkItem?

    /// Changes the icon to match the theme, after the colours have been still for a moment.
    static func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { sync() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }

    /// The icon that should be showing: the nearest theme's while the icon follows the theme, otherwise the picked one.
    static var wantedID: String {
        Prefs.shared.matchIcon ? nearest(Prefs.shared.colour1, Prefs.shared.colour2).id : Prefs.shared.iconChoice
    }

    /// The theme id of the icon that is showing now.
    static var activeID: String {
        guard let name = UIApplication.shared.alternateIconName, name.hasPrefix("AppIcon-") else { return ThemePreset.standard.id }
        return String(name.dropFirst("AppIcon-".count))
    }

    static func sync() { apply() }

    /// Puts the wanted icon on the home screen (nothing happens when it is already showing).
    static func apply() {
        let id = wantedID
        guard let preset = ThemePreset.all.first(where: { $0.id == id }) else { return }
        set(iconName(for: preset))
    }

    /// The person picked this icon: it stays, whatever the theme does.
    static func choose(_ preset: ThemePreset) {
        pending?.cancel()
        // Off first (turning it off remembers the icon showing now), then the choice, which is what gets applied.
        Prefs.shared.matchIcon = false
        Prefs.shared.iconChoice = preset.id
        apply()
    }

    private static func set(_ name: String?) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != name, app.applicationState == .active else { return }
        app.setAlternateIconName(name) { error in
            if let error { NSLog("iMC: could not change the app icon: %@", error.localizedDescription) }
        }
    }
}

/// A small picture of one of the app icons for the picker: the sky, the ground and the dirt block, in the theme's colours.
/// (The real icons are the files tools/make_app_icon.py draws; iOS does not let an app load its own icon files by name.)
struct IconPreview: View {
    let preset: ThemePreset
    var size: CGFloat = 72

    var body: some View {
        let c1 = Palette.plain(hex: preset.first), c2 = Palette.plain(hex: preset.second)
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.13), Color(red: 0.055, green: 0.078, blue: 0.18)], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.clear, c1.opacity(0.30)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color(red: 0.04, green: 0.06, blue: 0.10)).overlay(c2.opacity(0.24)).frame(height: size * 0.36)
            BrandMark().frame(width: size * 0.72, height: size * 0.72).offset(y: -size * 0.06)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .accessibilityHidden(true)
    }
}
