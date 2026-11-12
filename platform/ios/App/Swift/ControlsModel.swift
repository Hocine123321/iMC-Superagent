import SwiftUI
import UIKit

// MARK: - horizon-imc.txt (the game's own settings, edited here too)

/// The settings the game keeps in `home/horizon-imc.txt` (horizon-client-input/src/imc_settings.rs). The launcher
/// writes the same file in the same format; the game clamps every value when it reads it, so a bad line can never
/// give it a stick that cannot move. The game must not be running while the launcher changes it (it is not: the
/// launcher and the game are separate runs of the app).
enum ImcSchema {
    enum Kind { case flag, steps(Int) }
    struct Entry { let key: String; let kind: Kind; let fallback: Int }

    /// In the order the game writes them.
    static let entries: [Entry] = [
        Entry(key: "touchControls", kind: .flag, fallback: 1),
        Entry(key: "lookSpeed", kind: .steps(5), fallback: 2),
        Entry(key: "stickSize", kind: .steps(4), fallback: 1),
        Entry(key: "moveZone", kind: .steps(4), fallback: 1),
        Entry(key: "holdTime", kind: .steps(4), fallback: 1),
        Entry(key: "doubleTapJump", kind: .flag, fallback: 0),
        Entry(key: "safeMargin", kind: .steps(4), fallback: 2),
        Entry(key: "autoSprint", kind: .flag, fallback: 0),
        Entry(key: "greyUnused", kind: .flag, fallback: 0),
        Entry(key: "menuTouch", kind: .steps(5), fallback: 1),
        Entry(key: "buttonShiftX", kind: .steps(5), fallback: 2),
        Entry(key: "buttonShiftY", kind: .steps(5), fallback: 2),
        Entry(key: "shiftX", kind: .steps(5), fallback: 2),
        Entry(key: "shiftY", kind: .steps(5), fallback: 2),
        Entry(key: "autoPerformance", kind: .flag, fallback: 0),
        Entry(key: "autoSensitivity", kind: .steps(3), fallback: 1),
        Entry(key: "autoMinDistance", kind: .steps(6), fallback: 2),
        Entry(key: "autoFarTerrain", kind: .flag, fallback: 1),
        Entry(key: "autoRenderDistance", kind: .flag, fallback: 1),
        Entry(key: "autoResolution", kind: .flag, fallback: 0),
        Entry(key: "cursorInventory", kind: .flag, fallback: 0),
        Entry(key: "cursorSpeed", kind: .steps(5), fallback: 2),
    ]

    static func entry(_ key: String) -> Entry? { entries.first { $0.key == key } }
}

enum ImcFile {
    static var path: String { DiagFiles.path("home", "horizon-imc.txt") }

    /// Lines the game will ignore (it keeps the default for that setting).
    static func problems(in text: String) -> [String] {
        var bad: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let colon = line.firstIndex(of: ":") else { bad.append("\"\(line.prefix(30))\" has no colon"); continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard let e = ImcSchema.entry(key) else { continue }   // an unknown key is simply not used
            switch e.kind {
            case .flag: if value != "true" && value != "false" { bad.append("\(key): \(value.prefix(12))") }
            case .steps(let n): if let v = Int(value), v >= 0, v < n {} else { bad.append("\(key): \(value.prefix(12))") }
            }
        }
        return bad
    }
}

/// Reads and writes the file; every change is saved at once.
final class ImcStore: ObservableObject {
    @Published private(set) var values: [String: Int] = [:]

    init() { load() }

    func load() {
        var v: [String: Int] = [:]
        for e in ImcSchema.entries { v[e.key] = e.fallback }
        if let text = DiagFiles.text(ImcFile.path) {
            for raw in text.components(separatedBy: "\n") {
                guard let colon = raw.firstIndex(of: ":") else { continue }
                let key = raw[..<colon].trimmingCharacters(in: .whitespaces)
                let value = raw[raw.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                guard let e = ImcSchema.entry(key) else { continue }
                switch e.kind {
                case .flag: if value == "true" { v[key] = 1 } else if value == "false" { v[key] = 0 }
                case .steps(let n): if let i = Int(value), i >= 0, i < n { v[key] = i }
                }
            }
        }
        values = v
    }

    func int(_ key: String) -> Int { values[key] ?? ImcSchema.entry(key)?.fallback ?? 0 }
    func bool(_ key: String) -> Bool { int(key) != 0 }

    func set(_ key: String, _ value: Int) {
        guard values[key] != value else { return }
        values[key] = value
        save()
    }

    func set(_ key: String, _ value: Bool) { set(key, value ? 1 : 0) }

    func binding(_ key: String) -> Binding<Bool> { Binding(get: { self.bool(key) }, set: { self.set(key, $0) }) }
    func stepBinding(_ key: String) -> Binding<Int> { Binding(get: { self.int(key) }, set: { self.set(key, $0) }) }

    var isDefault: Bool { ImcSchema.entries.allSatisfy { int($0.key) == $0.fallback } }

    func reset() {
        for e in ImcSchema.entries { values[e.key] = e.fallback }
        try? FileManager.default.removeItem(atPath: ImcFile.path)
    }

    private func save() {
        var s = ""
        for e in ImcSchema.entries {
            let v = int(e.key)
            switch e.kind {
            case .flag: s += "\(e.key):\(v != 0)\n"
            case .steps: s += "\(e.key):\(v)\n"
            }
        }
        try? FileManager.default.createDirectory(atPath: DiagFiles.home, withIntermediateDirectories: true)
        try? s.write(toFile: ImcFile.path, atomically: true, encoding: .utf8)
    }
}

// MARK: - horizon-touch-layout.txt

struct TouchSlot: Equatable {
    var dx: Double = 0, dy: Double = 0, scale: Double = 1, opacity: Double = 1, shown = true

    static let maxMove = 1.0, minScale = 0.5, maxScale = 2.0, minOpacity = 0.15

    var isDefault: Bool { dx == 0 && dy == 0 && scale == 1 && opacity == 1 && shown }

    func clamped() -> TouchSlot {
        func fix(_ v: Double, _ lo: Double, _ hi: Double, _ fallback: Double) -> Double { v.isFinite ? min(hi, max(lo, v)) : fallback }
        return TouchSlot(dx: fix(dx, -Self.maxMove, Self.maxMove, 0), dy: fix(dy, -Self.maxMove, Self.maxMove, 0),
                         scale: fix(scale, Self.minScale, Self.maxScale, 1), opacity: fix(opacity, Self.minOpacity, 1, 1), shown: shown)
    }

    /// The rectangle `base` becomes in this arrangement on a screen of `size`, kept fully on the screen. The size changes
    /// around the centre (touch_layout.rs: Slot::place).
    func place(_ base: CGRect, in size: CGSize) -> CGRect {
        let s = clamped()
        if s.dx == 0 && s.dy == 0 && s.scale == 1 { return base }
        let nw = base.width * s.scale, nh = base.height * s.scale
        let cx = base.midX + s.dx * size.width, cy = base.midY + s.dy * size.height
        let nx = max(0, min(cx - nw / 2, size.width - nw)), ny = max(0, min(cy - nh / 2, size.height - nh))
        return CGRect(x: nx, y: ny, width: nw, height: nh)
    }

    /// The nudge that moves a button from where `base` is to `target` (Slot::moved_to), keeping this slot's size and opacity.
    func moved(base: CGRect, to target: CGRect, in size: CGSize) -> TouchSlot {
        var s = clamped()
        s.dx = size.width > 0 ? Double((target.midX - base.midX) / size.width) : 0
        s.dy = size.height > 0 ? Double((target.midY - base.midY) / size.height) : 0
        return s.clamped()
    }
}

struct TouchPad: Identifiable {
    enum Anchor { case topLeft(CGFloat, CGFloat, CGFloat, CGFloat), topRight(CGFloat, CGFloat, CGFloat, CGFloat), bottomRight(CGFloat, CGFloat, CGFloat, CGFloat), back }
    let id: Int          // the button's place in the layout file (touch_layout::NAMES)
    let name: String
    let label: String
    let title: String
    let anchor: Anchor

    /// Where the layout puts the button before the player's arrangement (touch.rs: Pad::rect, back::rect).
    func base(in size: CGSize, margin: CGFloat) -> CGRect {
        let w = size.width, h = size.height
        let side = 0.08 * margin, top = 0.04 * margin, bottom = 0.07 * margin
        let left = w * side, right = w * (1 - side), topY = h * top, bottomY = h * (1 - bottom)
        switch anchor {
        case .topLeft(let dx, let dy, let bw, let bh): return CGRect(x: left + dx * w, y: topY + dy * h, width: bw * w, height: bh * h)
        case .topRight(let dx, let dy, let bw, let bh): return CGRect(x: right - dx * w - bw * w, y: topY + dy * h, width: bw * w, height: bh * h)
        case .bottomRight(let dx, let dy, let bw, let bh): return CGRect(x: right - dx * w - bw * w, y: bottomY - dy * h - bh * h, width: bw * w, height: bh * h)
        case .back: return CGRect(x: w * 0.02, y: h * 0.04, width: w * 0.11, height: h * 0.13)
        }
    }

    static let all: [TouchPad] = [
        TouchPad(id: 0, name: "jump", label: "Jump", title: "Jump", anchor: .bottomRight(0.0, 0.02, 0.09, 0.20)),
        TouchPad(id: 1, name: "sneak", label: "Sneak", title: "Sneak", anchor: .bottomRight(0.10, 0.02, 0.08, 0.17)),
        TouchPad(id: 2, name: "run", label: "Run", title: "Run", anchor: .bottomRight(0.10, 0.21, 0.08, 0.17)),
        TouchPad(id: 3, name: "use", label: "Use", title: "Use", anchor: .bottomRight(0.0, 0.24, 0.09, 0.18)),
        TouchPad(id: 4, name: "pause", label: "Pause", title: "Pause", anchor: .topLeft(0.0, 0.0, 0.07, 0.13)),
        TouchPad(id: 5, name: "prev", label: "<", title: "Previous slot", anchor: .topLeft(0.22, 0.0, 0.06, 0.13)),
        TouchPad(id: 6, name: "next", label: ">", title: "Next slot", anchor: .topRight(0.22, 0.0, 0.06, 0.13)),
        TouchPad(id: 7, name: "drop", label: "Drop", title: "Drop", anchor: .topRight(0.10, 0.0, 0.08, 0.13)),
        TouchPad(id: 8, name: "inv", label: "Inv", title: "Inventory", anchor: .topRight(0.0, 0.0, 0.09, 0.13)),
        TouchPad(id: 9, name: "back", label: "Back", title: "Back (in menus)", anchor: .back),
    ]
}

enum TouchLayoutFile {
    static let fileName = "horizon-touch-layout.txt"
    static var path: String { DiagFiles.path("home", fileName) }
    /// The buttons by their saved name (touch_layout::NAMES). The ones after "back" are the game's extra buttons, which
    /// the launcher does not edit but keeps when it saves.
    static let names = ["jump", "sneak", "run", "use", "pause", "prev", "next", "drop", "inv", "back", "chat", "debug", "shot", "view", "key1", "key2"]

    private static func parseLine(_ line: String) -> (Int, TouchSlot)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let name = line[..<colon].trimmingCharacters(in: .whitespaces)
        guard let index = names.firstIndex(of: name) else { return nil }
        let parts = line[line.index(after: colon)...].split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 5, let dx = Double(parts[0]), let dy = Double(parts[1]), let sc = Double(parts[2]), let op = Double(parts[3]),
              parts[4] == "true" || parts[4] == "false" else { return nil }
        return (index, TouchSlot(dx: dx, dy: dy, scale: sc, opacity: op, shown: parts[4] == "true").clamped())
    }

    /// How many buttons the file customises, and how many of its lines the game cannot read.
    static func validate(_ text: String) -> (custom: Int, bad: Int) {
        var custom = 0, bad = 0
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let colon = line.firstIndex(of: ":"), names.contains(line[..<colon].trimmingCharacters(in: .whitespaces)) else { continue }
            if let (_, s) = parseLine(line) { if !s.isDefault { custom += 1 } } else { bad += 1 }
        }
        return (custom, bad)
    }

    static func parse(_ text: String) -> [TouchSlot] {
        var slots = Array(repeating: TouchSlot(), count: names.count)
        for line in text.components(separatedBy: "\n") { if let (i, s) = parseLine(line) { slots[i] = s } }
        return slots
    }

    /// Only the buttons that differ from the default; the extra buttons' lines are kept as they were.
    static func serialize(_ slots: [TouchSlot], keeping existing: String) -> String {
        var out = ""
        for (i, name) in names.enumerated() where i < slots.count {
            let s = slots[i].clamped()
            if i >= 10 {
                // Extras: keep the game's own line as it is.
                if let line = existing.components(separatedBy: "\n").first(where: { $0.hasPrefix(name + ":") }) { out += line + "\n" }
                continue
            }
            if s.isDefault { continue }
            out += "\(name):" + String(format: "%.4f,%.4f,%.3f,%.3f,", s.dx, s.dy, s.scale, s.opacity) + "\(s.shown)\n"
        }
        return out
    }
}
