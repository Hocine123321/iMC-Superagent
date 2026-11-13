import SwiftUI
import UIKit

/// What the Play tab shows, read from the existing Objective-C model (HZLauncherModel). No rules live here.
@MainActor
final class LauncherState: ObservableObject {
    enum Files { case checking, missing, damaged(String), ready }

    @Published var files: Files = .checking
    @Published var resourceBytes: Int64 = 0
    @Published var freeBytes: Int64 = 0
    @Published var accountName: String? = nil
    @Published var accountUUID: String? = nil
    @Published var accountOwns = false
    @Published var hasCrash = false
    @Published var startFailed = false

    var isReady: Bool { if case .ready = files { return true } else { return false } }

    /// The Objective-C header has no nullability annotations, so shared() imports as optional.
    private var model: HZLauncherModel { HZLauncherModel.shared()! }

    private var refreshing = false
    private var refreshAgain = false

    /// Reads the state of the game files, the account, the crash report and the disk. Every one of those is file
    /// work, and the first version did all of it on the main thread at every tab change, page push and return to the
    /// app: the manifest was parsed, the folder listed, up to 64 KB of each crash report read and analysed, all
    /// before the next frame could be drawn. Now the reading happens on a utility queue and only the result is
    /// published on the main thread. A refresh asked for while one is running runs once more afterwards, not in
    /// parallel and not once per request.
    func refresh() {
        if refreshing { refreshAgain = true; return }
        refreshing = true
        let model = self.model
        let root = model.root as String
        let resources = model.resources as String
        DispatchQueue.global(qos: .userInitiated).async {
            // Stage 1: what the Play tab needs to show Play. The files check no longer parses the whole manifest when it
            // passed before with the same size and date (LauncherModel.m), so this returns in milliseconds.
            var problem: NSString?
            let state = model.checkFiles(&problem)
            let account = HZAccountStore.shared().account()
            let name = account?.name, uuid = account?.uuid, owns = account?.owns ?? false
            let free = Self.freeSpace(at: root)
            let why = (problem as String?) ?? ""
            DispatchQueue.main.async {
                switch state {
                case .missing: self.files = .missing
                case .damaged: self.files = .damaged(why)
                case .ready: self.files = .ready
                @unknown default: self.files = .missing
                }
                self.accountName = name
                self.accountUUID = uuid
                self.accountOwns = owns
                self.freeBytes = free
                if state != .ready { self.resourceBytes = 0 }
            }
            // Stage 2: the slower things, shown when they arrive. The size of the files is walked once per manifest and
            // remembered (walking thousands of files at every tab change was most of the old "Checking the game files").
            var crash = false
            if let c = CrashFiles.newest() { crash = c.date.timeIntervalSince1970 > LauncherFile.number("crashSeen", default: 0) }
            var size: Int64 = 0
            if state == .ready {
                let sig = Self.manifestSignature(resources)
                if let sig, LauncherFile.get("resourcesKey") == sig {
                    size = Int64(LauncherFile.number("resourcesBytes", default: 0))
                } else {
                    size = Int64(clamping: model.resourcesSize())
                    if let sig { LauncherFile.set("resourcesKey", sig); LauncherFile.set("resourcesBytes", String(size)) }
                }
            }
            DispatchQueue.main.async {
                self.hasCrash = crash
                self.resourceBytes = size
                self.refreshing = false
                if self.refreshAgain { self.refreshAgain = false; self.refresh() }
            }
        }
    }

    /// "size-date" of the manifest, the same text LauncherModel.m keeps as `filesOK:`. Changes whenever the files are
    /// replaced, imported again or deleted.
    nonisolated static func manifestSignature(_ resources: String) -> String? {
        let path = (resources as NSString).appendingPathComponent("horizon-resources.json")
        guard let a = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (a[.size] as? NSNumber)?.uint64Value, let date = a[.modificationDate] as? Date else { return nil }
        return "\(size)-\(Int64(date.timeIntervalSince1970))"
    }

    init() {
        // Paint the last known answer at once: the same manifest, unchanged since it last passed, is still ready. The
        // refresh that follows confirms it (or downgrades it) a moment later.
        let resources = model.resources as String
        if let sig = Self.manifestSignature(resources), LauncherFile.get("filesOK") == sig {
            files = .ready
            resourceBytes = Int64(LauncherFile.number("resourcesBytes", default: 0))
        }
    }

    nonisolated static func freeSpace(at path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        if let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let n = v.volumeAvailableCapacityForImportantUsage { return n }
        if let a = try? FileManager.default.attributesOfFileSystem(forPath: path), let n = a[.systemFreeSize] as? NSNumber { return n.int64Value }
        return 0
    }

    /// The same Play as before: the game is a separate run of the app, so leave the one-shot flag and exit.
    /// (Replaced by an in-process start in M24 stage 3.)
    func play() {
        HZTheme.flushSettings()      // the game reads launcher.txt itself, and may be a new run of the app
        // Play without closing the app (flag inProcessPlay:true): the engine is already running and waiting.
        if HZIsInProcessPlay() { playInProcess(); return }
        guard model.setStartGameFlag() else { startFailed = true; return }
        HorizonCrashReporterCleanExit()
        exit(0)
    }

    /// The engine waits for Play. The account is written now (the engine refuses a file older than two minutes and
    /// reads it when it loads), then the engine is released and the launcher goes away. A failure leaves the
    /// launcher up and says so; nothing is half done, because the engine only loads on `horizon_ios_play()`.
    private func playInProcess() {
        let root = model.root as String
        var problem: NSString?
        guard model.checkFiles(&problem) == .ready else { refresh(); startFailed = true; return }
        HZRemoveStaleGameSession(root)
        let session = HZWriteGameSession(root)          // nil: not signed in, the game starts offline as before
        HZNoteGameSession(root, session != nil)
        guard horizon_ios_play() else { startFailed = true; return }
        EngineOverlay.dismiss()
    }

    func cancelPlay() { _ = model.consumeStartGameFlag() }
}

enum ByteText {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
