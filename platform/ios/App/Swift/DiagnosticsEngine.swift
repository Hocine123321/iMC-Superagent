import SwiftUI
import UIKit
import Metal
import Network

// MARK: - Results

enum CheckStatus { case pending, running, pass, warn, fail, info }

struct Outcome {
    var status: CheckStatus
    var detail: String
    var advice: String? = nil
}

struct CheckDef: Identifiable {
    let id: String
    let group: String
    let title: String
    let symbol: String
    let run: () async -> Outcome
}

struct CheckResult: Identifiable {
    let id: String
    let group: String
    let title: String
    let symbol: String
    var status: CheckStatus
    var detail: String
    var advice: String?
}

// MARK: - Small file helpers

enum DiagFiles {
    static var root: String { LauncherFile.root }
    static var home: String { (root as NSString).appendingPathComponent("home") }
    static func path(_ parts: String...) -> String { parts.reduce(root) { ($0 as NSString).appendingPathComponent($1) } }

    static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    static func text(_ path: String) -> String? { try? String(contentsOfFile: path, encoding: .utf8) }

    /// The last `maxBytes` of a file as text (a log can be megabytes).
    static func tail(_ path: String, maxBytes: Int = 262_144) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? h.seek(toOffset: start)
        guard let data = try? h.readToEnd() else { return nil }
        var s = String(decoding: data, as: UTF8.self)
        if start > 0, let nl = s.firstIndex(of: "\n") { s = String(s[s.index(after: nl)...]) }   // drop the cut first line
        return s
    }

    static func modified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    static func size(of path: String) -> UInt64 {
        let url = URL(fileURLWithPath: path)
        var total: UInt64 = 0
        guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: []) else {
            return ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.uint64Value ?? 0
        }
        for case let f as URL in en {
            if let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), v.isRegularFile == true { total += UInt64(v.fileSize ?? 0) }
        }
        return total
    }

    static func count(in path: String, suffix: String) -> Int {
        guard let en = FileManager.default.enumerator(atPath: path) else { return 0 }
        var n = 0
        for case let rel as String in en where rel.hasSuffix(suffix) { n += 1 }
        return n
    }

    static func bytes(_ n: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: n), countStyle: .file) }
    static func ago(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Crash reports

struct CrashInfo {
    enum Kind { case systemEnd, signal, exception, rustPanic, unknown }
    let url: URL
    let date: Date
    let kind: Kind
    let headline: String
    let detail: String
    let advice: String
    let text: String
}

enum CrashFiles {
    /// The newest report that records a crash: crash.txt (only if it holds a signal, an exception or a system kill, as it
    /// is rewritten at every launch), the kept crash-previous.txt, or the engine's own report in home/crash-reports.
    static func newest() -> CrashInfo? {
        var found: [(URL, Date)] = []
        let fm = FileManager.default
        func consider(_ path: String, requiresMarker: Bool) {
            guard let d = DiagFiles.modified(path), let t = DiagFiles.tail(path, maxBytes: 65_536) else { return }
            if requiresMarker && !isCrash(t) { return }
            found.append((URL(fileURLWithPath: path), d))
        }
        consider(DiagFiles.path("crash.txt"), requiresMarker: true)
        consider(DiagFiles.path("crash-previous.txt"), requiresMarker: false)
        let dir = (DiagFiles.home as NSString).appendingPathComponent("crash-reports")
        if let names = try? fm.contentsOfDirectory(atPath: dir) {
            for n in names where !n.hasPrefix(".") { consider((dir as NSString).appendingPathComponent(n), requiresMarker: false) }
        }
        guard let best = found.max(by: { $0.1 < $1.1 }), let text = DiagFiles.tail(best.0.path, maxBytes: 65_536) else { return nil }
        return analyze(url: best.0, date: best.1, text: text)
    }

    static func isCrash(_ t: String) -> Bool {
        t.contains("=== FATAL SIGNAL") || t.contains("=== UNCAUGHT") || t.contains("=== PREVIOUS RUN ENDED")
    }

    private static func line(_ text: String, prefix: String) -> String? {
        for l in text.components(separatedBy: "\n") where l.hasPrefix(prefix) { return String(l.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) }
        return nil
    }

    static func analyze(url: URL, date: Date, text: String) -> CrashInfo {
        let breadcrumb = line(text, prefix: "breadcrumb:") ?? "none recorded"
        if text.contains("=== PREVIOUS RUN ENDED") {
            let mem = line(text, prefix: "last seen:") ?? ""
            return CrashInfo(url: url, date: date, kind: .systemEnd, headline: "The system ended the app",
                             detail: "No crash was recorded, so iOS most likely stopped the app for using too much memory. Last step reached: \(breadcrumb)." + (mem.isEmpty ? "" : " Memory last seen: \(mem).") ,
                             advice: "Turn on Auto Performance (Controls > Performance), lower the render distance in the game, and close other apps before playing.",
                             text: text)
        }
        if text.contains("=== FATAL SIGNAL") {
            let sig = line(text, prefix: "signal:") ?? "?"
            let name: String
            switch Int(sig.split(separator: " ").first ?? "") ?? 0 {
            case 11: name = "SIGSEGV (bad memory access)"
            case 10: name = "SIGBUS (bad memory access)"
            case 4: name = "SIGILL (illegal instruction)"
            case 6: name = "SIGABRT (the app stopped itself)"
            case 5: name = "SIGTRAP (a Swift or runtime trap)"
            case 8: name = "SIGFPE (arithmetic error)"
            case 12: name = "SIGSYS (bad system call)"
            default: name = "signal \(sig)"
            }
            return CrashInfo(url: url, date: date, kind: .signal, headline: "Crash: \(name)",
                             detail: "Last step reached: \(breadcrumb).",
                             advice: "Share the crash report from the Logs tab so the cause can be found. If it happens at the same step every time, note which one.",
                             text: text)
        }
        if text.contains("=== UNCAUGHT") {
            let name = line(text, prefix: "name:") ?? "exception"
            let reason = line(text, prefix: "reason:") ?? ""
            return CrashInfo(url: url, date: date, kind: .exception, headline: "Crash: \(name)",
                             detail: reason.isEmpty ? "Last step reached: \(breadcrumb)." : "\(reason). Last step reached: \(breadcrumb).",
                             advice: "Share the crash report from the Logs tab so the cause can be found.", text: text)
        }
        // The engine's own report (a Rust panic).
        let first = text.components(separatedBy: "\n").first(where: { $0.lowercased().contains("panick") }) ?? text.components(separatedBy: "\n").first ?? ""
        return CrashInfo(url: url, date: date, kind: .rustPanic, headline: "The game reported a crash",
                         detail: String(first.prefix(240)),
                         advice: "Share the crash report from the Logs tab so the cause can be found.", text: text)
    }
}

// MARK: - Session log

struct SessionSample { let t: Double; let footprint: Double?; let available: Double?; let thermal: Int }

struct SessionStats {
    let samples: [SessionSample]
    let duration: Double
    let peakFootprint: Double?
    let minAvailable: Double?
    let maxThermal: Int
    let lowPowerSeen: Bool

    static func read(path: String) -> SessionStats? {
        guard let text = DiagFiles.tail(path, maxBytes: 1_000_000) else { return nil }
        var out: [SessionSample] = []
        var lowPower = false
        for l in text.components(separatedBy: "\n") {
            let c = l.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard c.count >= 5, let t = Double(c[0]) else { continue }
            out.append(SessionSample(t: t, footprint: Double(c[1]), available: Double(c[2]), thermal: Int(c[3]) ?? 0))
            if c[4] == "1" { lowPower = true }
        }
        guard !out.isEmpty else { return nil }
        return SessionStats(samples: out, duration: out.last?.t ?? 0,
                            peakFootprint: out.compactMap { $0.footprint }.max(),
                            minAvailable: out.compactMap { $0.available }.filter { $0 > 0 }.min(),
                            maxThermal: out.map { $0.thermal }.max() ?? 0, lowPowerSeen: lowPower)
    }
}

// MARK: - The suite

enum DiagnosticsSuite {
    static func marketingName(_ id: String) -> String? {
        let names: [String: String] = [
            "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE (2nd generation)",
            "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,6": "iPhone SE (3rd generation)", "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
        ]
        return names[id]
    }

    static func mb(_ bytes: UInt64) -> Int { Int(bytes / 1_048_576) }

    private static func urlProblem(_ error: Error) -> String {
        guard let e = error as? URLError else { return error.localizedDescription }
        switch e.code {
        case .notConnectedToInternet: return "no internet connection"
        case .timedOut: return "no answer within 8 seconds"
        case .cannotFindHost, .dnsLookupFailed: return "the address could not be looked up (DNS)"
        case .cannotConnectToHost: return "the server refused the connection"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid, .clientCertificateRejected:
            return "the secure connection failed (a network filter, or a wrong date and time on this phone, can cause this)"
        case .networkConnectionLost: return "the connection dropped"
        default: return e.localizedDescription
        }
    }

    /// One HTTPS request. Any HTTP answer means the server can be reached; only an error means it cannot.
    private static func probe(_ title: String, url: String, get: Bool = false) async -> Outcome {
        guard let u = URL(string: url) else { return Outcome(status: .fail, detail: "Bad address.") }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        var req = URLRequest(url: u)
        req.httpMethod = get ? "GET" : "HEAD"
        let started = Date()
        do {
            let (data, resp) = try await URLSession(configuration: config).data(for: req)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            var detail = "Answered in \(ms) ms (HTTP \(code))."
            if get && !data.isEmpty && ms > 0 {
                let mbit = Double(data.count) * 8 / 1_000_000 / (Double(ms) / 1000)
                detail += String(format: " Fetched %.0f KB at about %.1f Mbit/s (a small sample: the real download is faster once it gets going).", Double(data.count) / 1024, mbit)
            }
            if code >= 500 { return Outcome(status: .warn, detail: detail + " The server reports a problem of its own.", advice: "Try again later; this is not caused by the phone.") }
            if ms > 2500 { return Outcome(status: .warn, detail: detail + " That is slow.", advice: "Move closer to the router or switch networks; downloads will be slow.") }
            return Outcome(status: .pass, detail: detail)
        } catch {
            return Outcome(status: .fail, detail: "Could not reach \(u.host ?? title): \(urlProblem(error)).",
                           advice: "Check the connection. If other apps work, a content filter, VPN or private DNS may be blocking \(u.host ?? "it").")
        }
    }

    private static func connection() async -> NWPath {
        await withCheckedContinuation { cont in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "imc.diag.path")
            var done = false
            monitor.pathUpdateHandler = { path in
                if done { return }
                done = true
                monitor.cancel()
                cont.resume(returning: path)
            }
            monitor.start(queue: queue)
        }
    }

    // swiftlint:disable function_body_length
    @MainActor
    static func make() -> [CheckDef] {
        let prefs = Prefs.shared
        var defs: [CheckDef] = []
        func add(_ id: String, _ group: String, _ title: String, _ symbol: String, _ run: @escaping () async -> Outcome) {
            defs.append(CheckDef(id: id, group: group, title: title, symbol: symbol, run: run))
        }
        let useModrinth = prefs.useModrinth
        let showHead = prefs.showHead

        // ---- Phone
        add("device", "Phone", "Model and system", "iphone") {
            let id: String = HZDiagMachine() ?? "unknown"
            let version = await MainActor.run { UIDevice.current.systemVersion }
            let name = marketingName(id) ?? "Unknown model"
            return Outcome(status: .info, detail: "\(name) (\(id)), iOS \(version).")
        }
        add("ram", "Phone", "Memory", "memorychip") {
            let total = ProcessInfo.processInfo.physicalMemory
            let gb = Double(total) / 1_073_741_824
            if gb >= 5.5 { return Outcome(status: .pass, detail: String(format: "%.1f GB. Plenty for the game.", gb)) }
            if gb >= 3.4 { return Outcome(status: .info, detail: String(format: "%.1f GB. Enough with a modest render distance; the game is tuned for this.", gb)) }
            return Outcome(status: .warn, detail: String(format: "%.1f GB. Tight.", gb), advice: "Keep the render distance low and turn on Auto Performance.")
        }
        add("headroom", "Phone", "Memory left for the game", "gauge.with.dots.needle.33percent") {
            let avail = HZDiagAvailableMemory(), foot = HZDiagFootprint()
            if avail == 0 { return Outcome(status: .info, detail: "iOS reports no limit here (this happens in the simulator).") }
            let a = mb(UInt64(avail))
            let detail = "\(a) MB left before iOS ends the app, with \(mb(UInt64(foot))) MB in use now."
            if a < 400 { return Outcome(status: .fail, detail: detail, advice: "Close other apps, then reopen iMC Horizon. With this little room the game will be ended.") }
            if a < 900 { return Outcome(status: .warn, detail: detail, advice: "Close other apps for more room. Auto Performance can lower the render distance when memory runs short.") }
            return Outcome(status: .pass, detail: detail)
        }
        add("thermal", "Phone", "Temperature", "thermometer.medium") {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: return Outcome(status: .pass, detail: "Normal.")
            case .fair: return Outcome(status: .pass, detail: "Slightly warm. Nothing is slowed yet.")
            case .serious: return Outcome(status: .warn, detail: "Hot. iOS is slowing the phone down.", advice: "Let it cool before a long session; take it out of its case and out of the sun.")
            case .critical: return Outcome(status: .fail, detail: "Very hot. iOS is limiting the phone heavily.", advice: "Stop and let the phone cool down.")
            @unknown default: return Outcome(status: .info, detail: "Unknown.")
            }
        }
        add("lowpower", "Phone", "Low Power Mode", "bolt.badge.clock") {
            ProcessInfo.processInfo.isLowPowerModeEnabled
                ? Outcome(status: .warn, detail: "On. iOS lowers the frame rate and slows background work.", advice: "Turn Low Power Mode off in Settings > Battery for the best result.")
                : Outcome(status: .pass, detail: "Off.")
        }
        add("battery", "Phone", "Battery", "battery.75percent") {
            let (level, state) = await MainActor.run { () -> (Float, UIDevice.BatteryState) in
                UIDevice.current.isBatteryMonitoringEnabled = true
                return (UIDevice.current.batteryLevel, UIDevice.current.batteryState)
            }
            if level < 0 { return Outcome(status: .info, detail: "The battery level is not available here.") }
            let pct = Int((level * 100).rounded())
            let charging = state == .charging || state == .full
            if pct < 20 && !charging { return Outcome(status: .warn, detail: "\(pct) %, not charging.", advice: "Plug in. The game uses a lot of power, and iOS limits performance on a low battery.") }
            return Outcome(status: .pass, detail: "\(pct) %\(charging ? ", charging" : "").")
        }
        add("display", "Phone", "Screen", "display") {
            await MainActor.run {
                let s = UIScreen.main
                let px = CGSize(width: s.nativeBounds.width, height: s.nativeBounds.height)
                return Outcome(status: .info, detail: "\(Int(px.width)) x \(Int(px.height)) pixels, up to \(s.maximumFramesPerSecond) Hz.")
            }
        }
        add("gpu", "Phone", "Graphics (Metal)", "cpu") {
            guard let d = MTLCreateSystemDefaultDevice() else {
                return Outcome(status: .fail, detail: "No Metal device is available.", advice: "The game needs Metal and cannot run without it.")
            }
            var family = "unknown"
            let families: [(MTLGPUFamily, String)] = [(.apple8, "Apple 8"), (.apple7, "Apple 7"), (.apple6, "Apple 6"), (.apple5, "Apple 5"), (.apple4, "Apple 4")]
            if #available(iOS 17.0, *), d.supportsFamily(.apple9) { family = "Apple 9" }
            else if let f = families.first(where: { d.supportsFamily($0.0) }) { family = f.1 }
            let working = d.recommendedMaxWorkingSetSize
            let detail = "\(d.name), GPU family \(family), \(d.hasUnifiedMemory ? "shared memory" : "own memory"), the system recommends at most \(mb(working)) MB of GPU data, largest single buffer \(mb(UInt64(d.maxBufferLength))) MB."
            return d.supportsFamily(.apple4) ? Outcome(status: .pass, detail: detail)
                                             : Outcome(status: .warn, detail: detail, advice: "This GPU is older than the game is built for.")
        }

        // ---- Storage
        add("free", "Storage", "Free space", "externaldrive") {
            let free = LauncherState.freeSpace(at: DiagFiles.root)
            let detail = "\(DiagFiles.bytes(UInt64(max(0, free)))) free on this phone."
            if free < 1_500_000_000 { return Outcome(status: .fail, detail: detail, advice: "Free some space. The download needs about 2.5 GB while it works, and worlds grow.") }
            if free < 4_000_000_000 { return Outcome(status: .warn, detail: detail, advice: "Getting low. Leave room for worlds and downloads.") }
            return Outcome(status: .pass, detail: detail)
        }
        add("usage", "Storage", "What the Horizon folder holds", "internaldrive") {
            var parts: [String] = []
            var total: UInt64 = 0
            for name in ["resources", "minecraft", "home", "marketplace"] {
                let p = DiagFiles.path(name)
                guard DiagFiles.exists(p) else { continue }
                let s = DiagFiles.size(of: p)
                total += s
                parts.append("\(name) \(DiagFiles.bytes(s))")
            }
            if parts.isEmpty { return Outcome(status: .info, detail: "Nothing yet.") }
            return Outcome(status: .info, detail: parts.joined(separator: ", ") + ". Total \(DiagFiles.bytes(total)).")
        }
        add("partial", "Storage", "Unfinished downloads", "arrow.down.circle.dotted") {
            let n = DiagFiles.count(in: DiagFiles.path("minecraft"), suffix: ".part")
            if n == 0 { return Outcome(status: .pass, detail: "None.") }
            return Outcome(status: .info, detail: "\(n) partly downloaded file\(n == 1 ? "" : "s") from a stopped download.",
                           advice: "Open Download and tap Continue: finished files are kept and these are completed.")
        }

        // ---- Game files
        add("resources", "Game files", "Prepared game files", "shippingbox") {
            var problem: NSString?
            let state = HZLauncherModel.shared()!.checkFiles(&problem)
            switch state.rawValue {
            case 2: return Outcome(status: .pass, detail: "horizon-resources.json is present and valid. This is the test the game makes before it starts.")
            case 1: return Outcome(status: .fail, detail: (problem as String?) ?? "Damaged.", advice: "Import the game files again (Settings > Game files).")
            default: return Outcome(status: .warn, detail: "No prepared game files yet.", advice: "Import a prepared folder or download the game.")
            }
        }
        add("json", "Game files", "Data files are readable", "doc.text.magnifyingglass") {
            let dir = DiagFiles.path("resources")
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return Outcome(status: .info, detail: "No resources folder to check.") }
            var ok = 0, skipped = 0
            for n in names where n.hasSuffix(".json") {
                let p = (dir as NSString).appendingPathComponent(n)
                let size = (try? FileManager.default.attributesOfItem(atPath: p))?[.size] as? NSNumber
                if (size?.intValue ?? 0) > 80_000_000 { skipped += 1; continue }
                guard let d = try? Data(contentsOf: URL(fileURLWithPath: p), options: .mappedIfSafe),
                      (try? JSONSerialization.jsonObject(with: d, options: .fragmentsAllowed)) != nil else {
                    return Outcome(status: .fail, detail: "\(n) is empty or damaged.", advice: "Import the game files again (Settings > Game files).")
                }
                ok += 1
            }
            if ok == 0 && skipped == 0 { return Outcome(status: .info, detail: "No JSON files in the resources folder.") }
            return Outcome(status: .pass, detail: "\(ok) data file\(ok == 1 ? "" : "s") read without a problem" + (skipped > 0 ? "; \(skipped) very large one skipped." : "."))
        }
        add("minecraft", "Game files", "Downloaded Minecraft", "arrow.down.circle") {
            let p = DiagFiles.path("minecraft")
            guard DiagFiles.exists(p) else { return Outcome(status: .info, detail: "Not downloaded. Not needed if you imported prepared files.") }
            return Outcome(status: .info, detail: "\(DiagFiles.bytes(DiagFiles.size(of: p))) in the minecraft folder.")
        }
        add("packs", "Game files", "Installed packs and mods", "shippingbox.fill") {
            let n = HZMarketInstaller(home: DiagFiles.home).installed().count
            return Outcome(status: .info, detail: n == 0 ? "Nothing installed from the Marketplace." : "\(n) installed from the Marketplace.")
        }

        // ---- Network
        add("path", "Network", "Connection", "wifi") {
            let p = await connection()
            if p.status != .satisfied { return Outcome(status: .fail, detail: "No network connection.", advice: "Connect to Wi-Fi or mobile data.") }
            let kind = p.usesInterfaceType(.wifi) ? "Wi-Fi" : p.usesInterfaceType(.cellular) ? "Mobile data" : p.usesInterfaceType(.wiredEthernet) ? "Wired" : "Connected"
            if p.isConstrained { return Outcome(status: .warn, detail: "\(kind), Low Data Mode is on.", advice: "Turn Low Data Mode off for large downloads.") }
            if p.isExpensive { return Outcome(status: .warn, detail: "\(kind). Downloads count against your data plan.", advice: "Use Wi-Fi for the game download (about 673 MB).") }
            return Outcome(status: .pass, detail: "\(kind).")
        }
        add("net-ms", "Network", "Microsoft sign-in", "person.badge.key") {
            await probe("Microsoft", url: "https://login.microsoftonline.com/consumers/v2.0/.well-known/openid-configuration", get: true)
        }
        add("net-xbox", "Network", "Xbox Live", "gamecontroller") { await probe("Xbox Live", url: "https://user.auth.xboxlive.com/") }
        add("net-mcs", "Network", "Minecraft services", "server.rack") { await probe("Minecraft services", url: "https://api.minecraftservices.com/") }
        add("net-meta", "Network", "Mojang game files", "arrow.down.to.line") {
            await probe("Mojang", url: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json", get: true)
        }
        add("net-assets", "Network", "Mojang sounds and textures", "speaker.wave.2") { await probe("Mojang assets", url: "https://resources.download.minecraft.net/") }
        add("net-registry", "Network", "Horizon Marketplace", "shippingbox") { await probe("Horizon registry", url: HZMarketClient.indexURL() ?? "") }
        if useModrinth { add("net-modrinth", "Network", "Modrinth", "globe") { await probe("Modrinth", url: "https://api.modrinth.com/v2/", get: true) } }
        if showHead { add("net-skin", "Network", "Mojang skins", "person.crop.square") { await probe("Mojang skins", url: "https://sessionserver.mojang.com/") } }

        // ---- Account
        let accountName = HZAccountStore.shared().account()?.name
        let accountOwns = HZAccountStore.shared().account()?.owns ?? false
        let signInConfigured = HZActiveClientID() != nil
        let checkedAt = LauncherFile.number("accountChecked", default: 0)
        add("account", "Account", "Microsoft account", "person.crop.circle") {
            guard let n = accountName else { return Outcome(status: .info, detail: "Not signed in. You only need an account to download the game.") }
            if !accountOwns { return Outcome(status: .warn, detail: "\(n) is signed in, but ownership of Java Edition is not confirmed.", advice: "Open Account and tap Check again.") }
            let when = checkedAt > 0 ? " Last checked \(DiagFiles.ago(Date(timeIntervalSince1970: checkedAt)))." : ""
            return Outcome(status: .pass, detail: "\(n) owns Minecraft: Java Edition.\(when)")
        }
        add("signin", "Account", "Sign-in setup", "key") {
            signInConfigured ? Outcome(status: .pass, detail: HZSignInIsTestMode() ? "Test mode: another launcher's app ID is used (this phone only)." : "This build has its own Microsoft app ID.")
                             : Outcome(status: .warn, detail: "This build has no Microsoft sign-in set up.", advice: "Use Game files to import a prepared folder; downloading needs sign-in.")
        }

        // ---- Settings
        add("imc", "Settings", "Game settings file", "slider.horizontal.3") {
            let p = DiagFiles.path("home", "horizon-imc.txt")
            guard let text = DiagFiles.text(p) else { return Outcome(status: .pass, detail: "No file: every setting is at its default.") }
            let bad = ImcFile.problems(in: text)
            return bad.isEmpty ? Outcome(status: .pass, detail: "horizon-imc.txt is valid.")
                               : Outcome(status: .warn, detail: "\(bad.count) line\(bad.count == 1 ? "" : "s") the game will ignore: " + bad.prefix(3).joined(separator: "; ") + ".",
                                         advice: "Open Controls and change the setting once, or reset it, to rewrite the file.")
        }
        add("layout", "Settings", "Touch layout file", "hand.tap") {
            let p = DiagFiles.path("home", TouchLayoutFile.fileName)
            guard let text = DiagFiles.text(p) else { return Outcome(status: .pass, detail: "No file: the standard button layout is used.") }
            let (custom, bad) = TouchLayoutFile.validate(text)
            if bad > 0 { return Outcome(status: .warn, detail: "\(bad) line\(bad == 1 ? "" : "s") in the layout file are not valid and are ignored; \(custom) button\(custom == 1 ? "" : "s") customised.",
                                        advice: "Open Controls > Edit buttons and save, or reset the layout.") }
            return Outcome(status: .pass, detail: "\(custom) button\(custom == 1 ? "" : "s") customised.")
        }
        add("options", "Settings", "Minecraft options", "gearshape") {
            guard let text = DiagFiles.text(DiagFiles.path("home", "options.txt")) else { return Outcome(status: .info, detail: "No options.txt yet: the game's defaults apply.") }
            func value(_ key: String) -> String? { text.components(separatedBy: "\n").first { $0.hasPrefix(key + ":") }.map { String($0.dropFirst(key.count + 1)) } }
            var parts: [String] = []
            if let v = value("renderDistance") { parts.append("render distance \(v)") }
            if let v = value("simulationDistance") { parts.append("simulation distance \(v)") }
            if let v = value("maxFps") { parts.append("frame limit \(v)") }
            if let v = value("guiScale") { parts.append("GUI scale \(v)") }
            let rd = Int(value("renderDistance") ?? "") ?? 0
            if rd > 12 { return Outcome(status: .warn, detail: parts.joined(separator: ", ") + ".", advice: "A render distance above 12 is heavy on a phone. Lower it or turn on Auto Performance.") }
            return Outcome(status: .info, detail: parts.isEmpty ? "options.txt is present." : parts.joined(separator: ", ") + ".")
        }
        add("startup", "Settings", "Start-up", "power") {
            let unclean = Int((DiagFiles.text(DiagFiles.path("unclean-ends")) ?? "0").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            var parts: [String] = []
            if DiagFiles.exists(DiagFiles.path("open-launcher")) { parts.append("open-launcher flag set") }
            if unclean >= 3 { return Outcome(status: .warn, detail: "The app was ended without a signal \(unclean) times in a row.", advice: "That pattern means iOS keeps ending it for memory. Lower the render distance and turn on Auto Performance.") }
            if unclean > 0 { parts.append("\(unclean) unclean end\(unclean == 1 ? "" : "s") recorded") }
            return Outcome(status: .pass, detail: parts.isEmpty ? "Normal." : parts.joined(separator: ", ") + ".")
        }

        // ---- Last run
        add("crash", "Last run", "Crash reports", "exclamationmark.triangle") {
            guard let c = CrashFiles.newest() else { return Outcome(status: .pass, detail: "No crash has been recorded.") }
            let age = DiagFiles.ago(c.date)
            let recent = Date().timeIntervalSince(c.date) < 7 * 86_400
            return Outcome(status: recent ? .warn : .info, detail: "\(c.headline), \(age). \(c.detail)", advice: recent ? c.advice : nil)
        }
        add("session", "Last run", "Memory and heat during the last session", "chart.xyaxis.line") {
            guard let s = SessionStats.read(path: DiagFiles.path("session-log.csv")) else { return Outcome(status: .info, detail: "No session log yet. It is written while the app runs.") }
            var parts: [String] = ["\(Int(s.duration / 60)) min recorded"]
            if let p = s.peakFootprint { parts.append("peak use \(Int(p)) MB") }
            if let m = s.minAvailable { parts.append("lowest room left \(Int(m)) MB") }
            let thermalNames = ["normal", "warm", "hot", "very hot"]
            parts.append("hottest: \(thermalNames[min(max(s.maxThermal, 0), 3)])")
            if s.lowPowerSeen { parts.append("Low Power Mode was on") }
            let detail = parts.joined(separator: ", ") + "."
            if let m = s.minAvailable, m < 300 { return Outcome(status: .warn, detail: detail, advice: "The session came close to the memory limit. Lower the render distance or turn on Auto Performance.") }
            if s.maxThermal >= 2 { return Outcome(status: .warn, detail: detail, advice: "The phone got hot during the session; performance drops when it does.") }
            return Outcome(status: .pass, detail: detail)
        }
        add("log", "Last run", "Game log", "text.alignleft") {
            let p = DiagFiles.path("home", "logs", "latest.log")
            guard let t = DiagFiles.tail(p) else { return Outcome(status: .info, detail: "No game log yet. It appears after the game has run once.") }
            let lines = t.components(separatedBy: "\n")
            let errors = lines.filter { let l = $0.lowercased(); return l.contains("error") || l.contains("panicked") }
            let warns = lines.filter { $0.lowercased().contains("warn") }
            if errors.isEmpty { return Outcome(status: .pass, detail: "\(lines.count) lines, \(warns.count) warning\(warns.count == 1 ? "" : "s"), no errors.") }
            let last = errors.suffix(2).map { String($0.trimmingCharacters(in: .whitespaces).prefix(140)) }.joined(separator: " | ")
            return Outcome(status: .warn, detail: "\(errors.count) error line\(errors.count == 1 ? "" : "s"), \(warns.count) warning\(warns.count == 1 ? "" : "s"). Latest: \(last)",
                           advice: "Open the Logs tab, choose Game log and filter by Errors.")
        }

        // ---- Signing and JIT
        add("memlimit", "Signing", "Memory entitlements", "lock.shield") {
            let inc: String = HZDiagEntitlement("com.apple.developer.kernel.increased-memory-limit") ?? "(could not read)"
            let ext: String = HZDiagEntitlement("com.apple.developer.kernel.extended-virtual-addressing") ?? "(could not read)"
            let detail = "Increased memory limit: \(inc). Extended virtual addressing: \(ext)."
            if inc == "absent" { return Outcome(status: .warn, detail: detail, advice: "The signing tool removed the increased-memory-limit entitlement, so iOS applies its standard limit. Sign with a tool or account that keeps it.") }
            return Outcome(status: .pass, detail: detail)
        }
        add("jit", "Signing", "JIT and debugger", "hammer") {
            var err: Int32 = 0
            let flags = HZDiagCodeSigningFlags(&err)
            let allow: String = HZDiagEntitlement("com.apple.developer.cs.allow-jit") ?? "(could not read)"
            let task: String = HZDiagEntitlement("get-task-allow") ?? "(could not read)"
            if err != 0 { return Outcome(status: .info, detail: "The signing flags could not be read (error \(err)).") }
            let debugged = flags & 0x1000_0000 != 0
            return Outcome(status: .info, detail: "Debugger attached (JIT allowed by the system): \(debugged ? "yes" : "no"). allow-jit: \(allow). get-task-allow: \(task).")
        }
        add("probes", "Signing", "Executable-memory probes", "testtube.2") {
            guard let t = DiagFiles.text(DiagFiles.path("diagnostics.txt")) else { return Outcome(status: .info, detail: "No start-up report yet.") }
            let lines = t.components(separatedBy: "\n").filter { $0.contains("probe result:") || $0.contains("KILLED the app") }
            guard let last = lines.last else { return Outcome(status: .info, detail: "No probe has run. They are switched off by default; the Tools section can switch them on for the next start.") }
            return Outcome(status: .info, detail: String(last.trimmingCharacters(in: .whitespaces).prefix(220)))
        }
        return defs
    }
}

// MARK: - Runner

@MainActor
final class DiagnosticsRunner: ObservableObject {
    @Published var results: [CheckResult] = []
    @Published var running = false
    @Published var finished: Date? = nil
    @Published var done = 0

    var total: Int { results.count }
    var passes: Int { results.filter { $0.status == .pass }.count }
    var warnings: Int { results.filter { $0.status == .warn }.count }
    var problems: Int { results.filter { $0.status == .fail }.count }

    func run() {
        guard !running else { return }
        let defs = DiagnosticsSuite.make()
        results = defs.map { CheckResult(id: $0.id, group: $0.group, title: $0.title, symbol: $0.symbol, status: .pending, detail: "", advice: nil) }
        running = true; done = 0; finished = nil
        Task {
            // Four at a time: the slow ones are the network and folder checks, and they do not need each other.
            for start in stride(from: 0, to: defs.count, by: 4) {
                let batch = Array(defs[start..<min(start + 4, defs.count)])
                for d in batch { setStatus(d.id, .running) }
                let outcomes = await withTaskGroup(of: (String, Outcome).self) { group -> [(String, Outcome)] in
                    for d in batch { group.addTask { (d.id, await d.run()) } }
                    var collected: [(String, Outcome)] = []
                    for await item in group { collected.append(item) }
                    return collected
                }
                for (id, out) in outcomes { apply(id, out) }
            }
            running = false
            finished = Date()
            if problems > 0 { Haptics.warning() } else { Haptics.success() }
        }
    }

    private func setStatus(_ id: String, _ s: CheckStatus) {
        if let i = results.firstIndex(where: { $0.id == id }) { results[i].status = s }
    }

    private func apply(_ id: String, _ out: Outcome) {
        if let i = results.firstIndex(where: { $0.id == id }) {
            results[i].status = out.status; results[i].detail = out.detail; results[i].advice = out.advice
        }
        done += 1
    }

    // MARK: report

    func reportText() -> String {
        var s = "iMC Horizon check-up\n"
        s += "Date: \(Date())\n"
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        s += "Launcher: \(version)\n"
        s += "Result: \(passes) fine, \(warnings) to look at, \(problems) problem\(problems == 1 ? "" : "s")\n"
        var group = ""
        for r in results {
            if r.group != group { group = r.group; s += "\n== \(group) ==\n" }
            let mark: String
            switch r.status {
            case .pass: mark = "OK  "
            case .warn: mark = "WARN"
            case .fail: mark = "FAIL"
            case .info: mark = "INFO"
            default: mark = "... "
            }
            s += "[\(mark)] \(r.title): \(r.detail)\n"
            if let a = r.advice, r.status == .warn || r.status == .fail { s += "       -> \(a)\n" }
        }
        return s
    }

    func reportFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("imc-horizon-checkup.txt")
        do { try reportText().write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }
}
