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
        hasCrash = !((model.crashReportText() ?? "").isEmpty)
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
        guard model.setStartGameFlag() else { startFailed = true; return }
        HorizonCrashReporterCleanExit()
        exit(0)
    }

    func cancelPlay() { _ = model.consumeStartGameFlag() }
}

enum ByteText {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
