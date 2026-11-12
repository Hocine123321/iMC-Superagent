import SwiftUI
import Combine
import UIKit

/// launcher.txt: one "key:value" per line, shared with the Objective-C side (main.m reads openGame:, HZTheme reads
/// appearance: and glass:). Writing keeps every line this code does not own.
enum LauncherFile {
    static var root: String { HZLauncherModel.shared()!.root }
    static var path: String { (root as NSString).appendingPathComponent("launcher.txt") }

    // Reads and writes go through HZTheme's in-memory copy of the file (LauncherTheme.m): a read is a stat call and a
    // dictionary lookup, a write is in memory at once and on disk within half a second, a drag of a slider being one write.
    static func get(_ key: String) -> String? { HZTheme.setting(for: key) }

    static func set(_ key: String, _ value: String) { HZTheme.setSetting(value, for: key) }

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
        HZTheme.flushSettings()
        try? FileManager.default.removeItem(atPath: path)
        HZTheme.forgetSettings()
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

    // Developer options (unlocked by tapping the app mark in About three times; see DeveloperPage.swift)
    @Published var devMode: Bool { didSet { LauncherFile.set("devMode", String(devMode)) } }

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
        devMode = LauncherFile.flag("devMode", default: false)
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
        devMode = false
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

/// Only the accent colour, for the views at the top of the tree. `Prefs` has twenty settings in one observable object, and
/// a view that observes it is rebuilt when any of them changes: with the whole tab bar observing it, a slider drag in Look
/// rebuilt every tab sixty times a second. The tab bar needs to know about the accent and nothing else.
final class AccentLook: ObservableObject {
    static let shared = AccentLook()
    @Published private(set) var accent: Prefs.Accent
    private var watch: AnyCancellable?
    private init() {
        accent = Prefs.shared.accent
        watch = Prefs.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let a = Prefs.shared.accent
                if a != self.accent { self.accent = a }
            }
    }
    var brand: Color { accent == .red ? Palette.red : Palette.blue }
    var brand2: Color { accent == .red ? Palette.blue : Palette.red }
}

enum Haptics {
    // One generator of each kind, kept: making a new one for every tap costs a round trip to the haptics daemon, and
    // the first impact after a pause is late. `prepare()` after a tap keeps the engine awake for the next one.
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    static func tap() {
        guard Prefs.shared.haptics else { return }
        light.impactOccurred(); light.prepare()
    }
    static func select() {
        guard Prefs.shared.haptics else { return }
        selection.selectionChanged(); selection.prepare()
    }
    static func success() {
        guard Prefs.shared.haptics else { return }
        notification.notificationOccurred(.success)
    }
    static func warning() {
        guard Prefs.shared.haptics else { return }
        notification.notificationOccurred(.warning)
    }
}
