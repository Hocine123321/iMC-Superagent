import UIKit

/// The home screen icon follows the colour theme: each preset has an icon of its own (the dirt block lit in that
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

    static func sync() {
        guard Prefs.shared.matchIcon else { return }
        let preset = nearest(Prefs.shared.colour1, Prefs.shared.colour2)
        set(iconName(for: preset))
    }

    /// The app's own icon again (Match the icon was turned off).
    static func useDefault() {
        pending?.cancel()
        set(nil)
    }

    private static func set(_ name: String?) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != name, app.applicationState == .active else { return }
        app.setAlternateIconName(name) { error in
            if let error { NSLog("iMC: could not change the app icon: %@", error.localizedDescription) }
        }
    }
}
