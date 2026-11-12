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

    func refresh() {
        let model = self.model
        var problem: NSString?
        let state = model.checkFiles(&problem)
        switch state {
        case .missing: files = .missing
        case .damaged: files = .damaged((problem as String?) ?? "")
        case .ready: files = .ready
        @unknown default: files = .missing
        }
        let account = HZAccountStore.shared().account()
        accountName = account?.name
        accountUUID = account?.uuid
        accountOwns = account?.owns ?? false
        // A crash report the person has not opened yet (opening it in Diagnostics > Logs marks it seen).
        if let c = CrashFiles.newest() { hasCrash = c.date.timeIntervalSince1970 > LauncherFile.number("crashSeen", default: 0) } else { hasCrash = false }
        let root = model.root as String
        freeBytes = Self.freeSpace(at: root)
        if state == .ready {
            DispatchQueue.global(qos: .utility).async {
                let bytes = Int64(clamping: model.resourcesSize())
                DispatchQueue.main.async { self.resourceBytes = bytes }
            }
        } else {
            resourceBytes = 0
        }
    }

    static func freeSpace(at path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        if let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let n = v.volumeAvailableCapacityForImportantUsage { return n }
        if let a = try? FileManager.default.attributesOfFileSystem(forPath: path), let n = a[.systemFreeSize] as? NSNumber { return n.int64Value }
        return 0
    }

    /// The same Play as before: the game is a separate run of the app, so leave the one-shot flag and exit.
    /// (Replaced by an in-process start in M24 stage 3.)
    func play() {
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
