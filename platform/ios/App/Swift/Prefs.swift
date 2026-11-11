import SwiftUI
import UIKit

/// launcher.txt: one "key:value" per line, shared with the Objective-C side (main.m reads openGame:, HZTheme reads
/// appearance: and glass:). Writing keeps every line this code does not own.
enum LauncherFile {
    static var root: String { HZLauncherModel.shared()!.root }
    static var path: String { (root as NSString).appendingPathComponent("launcher.txt") }

    static func get(_ key: String) -> String? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let prefix = key + ":"
        for line in text.components(separatedBy: "\n") where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    static func set(_ key: String, _ value: String) {
        let old = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let prefix = key + ":"
        var kept = old.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix(prefix) }
        kept.append(prefix + value)
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        try? (kept.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func flag(_ key: String, default fallback: Bool) -> Bool {
        switch get(key) {
        case "true": return true
        case "false": return false
        default: return fallback
        }
    }

    static func number(_ key: String, default fallback: Double) -> Double {
        guard let text = get(key), let v = Double(text), v.isFinite else { return fallback }
        return v
    }

    /// Every launcher setting back to its default. The start-up line (openGame:) is a launcher setting too.
    static func resetAll() {
        try? FileManager.default.removeItem(atPath: path)
    }
}

/// What the person has chosen in Settings. Each value is saved the moment it changes.
final class Prefs: ObservableObject {
    static let shared = Prefs()

    enum Accent: String, CaseIterable, Identifiable {
        case blue, red
        var id: String { rawValue }
        var title: String { self == .blue ? "Blue" : "Red" }
    }

    // Look
    @Published var appearance: Int { didSet { HZTheme.setAppearance(HZAppearance(rawValue: appearance) ?? .system) } }
    @Published var accent: Accent { didSet { LauncherFile.set("accent", accent.rawValue) } }
    /// 0 is all blue, 1 is all red; the middle is an even mix behind the launcher.
    @Published var balance: Double { didSet { LauncherFile.set("balance", String(format: "%.2f", balance)) } }
    /// How strongly the colour shows behind the launcher (kept as "glass:" from the first version).
    @Published var intensity: Double { didSet { HZTheme.setGlassStrength(Float(intensity)) } }
    @Published var haptics: Bool { didSet { LauncherFile.set("haptics", String(haptics)) } }
    @Published var reduceMotion: Bool { didSet { HZPrefs.setReduceMotion(reduceMotion) } }
    @Published var compactLists: Bool { didSet { HZPrefs.setCompactLists(compactLists) } }
    @Published var showHead: Bool { didSet { LauncherFile.set("showHead", String(showHead)) } }

    // Game
    @Published var opensGameDirectly: Bool { didSet { HZLauncherModel.shared()!.opensGameDirectly = opensGameDirectly } }
    /// Play without closing the app (experimental). Read by main.m at launch, so a change needs the app restarted.
    @Published var inProcessPlay: Bool { didSet { HZLauncherModel.shared()!.inProcessPlay = inProcessPlay } }
    @Published var confirmPlay: Bool { didSet { LauncherFile.set("confirmPlay", String(confirmPlay)) } }
    @Published var keepAwake: Bool { didSet { LauncherFile.set("keepAwake", String(keepAwake)) } }

    // Marketplace
    @Published var useModrinth: Bool { didSet { HZPrefs.setUseModrinth(useModrinth) } }
    @Published var showMods: Bool { didSet { HZPrefs.setShowMods(showMods) } }
    @Published var showShaders: Bool { didSet { HZPrefs.setShowShaders(showShaders) } }
    @Published var showOtherKinds: Bool { didSet { HZPrefs.setShowOtherKinds(showOtherKinds) } }
    @Published var confirmInstalls: Bool { didSet { HZPrefs.setConfirmInstalls(confirmInstalls) } }

    var brand: Color { accent == .red ? Palette.red : Palette.blue }
    var brand2: Color { accent == .red ? Palette.blue : Palette.red }

    private init() {
        appearance = HZTheme.appearance().rawValue
        accent = Accent(rawValue: LauncherFile.get("accent") ?? "") ?? .blue
        balance = min(1, max(0, LauncherFile.number("balance", default: 0.5)))
        intensity = Double(HZTheme.glassStrength())
        haptics = LauncherFile.flag("haptics", default: true)
        reduceMotion = HZPrefs.reduceMotion()
        compactLists = HZPrefs.compactLists()
        showHead = LauncherFile.flag("showHead", default: true)
        opensGameDirectly = HZLauncherModel.shared()!.opensGameDirectly
        inProcessPlay = HZLauncherModel.shared()!.inProcessPlay
        confirmPlay = LauncherFile.flag("confirmPlay", default: true)
        keepAwake = LauncherFile.flag("keepAwake", default: true)
        useModrinth = HZPrefs.useModrinth()
        showMods = HZPrefs.showMods()
        showShaders = HZPrefs.showShaders()
        showOtherKinds = HZPrefs.showOtherKinds()
        confirmInstalls = HZPrefs.confirmInstalls()
    }

    /// Puts the launcher's own settings back. The game's settings (touch, performance) and the files are not touched.
    func resetLauncherSettings() {
        LauncherFile.resetAll()
        appearance = HZAppearance.system.rawValue
        accent = .blue
        balance = 0.5
        intensity = 0.5
        haptics = true
        showHead = true
        confirmPlay = true
        keepAwake = true
        opensGameDirectly = false
        inProcessPlay = false
        useModrinth = false
        showMods = false
        showShaders = false
        showOtherKinds = false
        confirmInstalls = true
        compactLists = false
        reduceMotion = false
    }
}

enum Haptics {
    static func tap() {
        guard Prefs.shared.haptics else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func select() {
        guard Prefs.shared.haptics else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func success() {
        guard Prefs.shared.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        guard Prefs.shared.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
