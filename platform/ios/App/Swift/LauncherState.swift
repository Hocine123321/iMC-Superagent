import SwiftUI
import UIKit

/// What the Play tab shows, read from the existing Objective-C model (HZLauncherModel). No rules live here.
@MainActor
final class LauncherState: ObservableObject {
    enum Files { case checking, missing, damaged(String), ready }

    @Published var files: Files = .checking
    @Published var sizeText: String = ""
    @Published var accountName: String? = nil
    @Published var startFailed = false

    var isReady: Bool { if case .ready = files { return true } else { return false } }

    func refresh() {
        let model = HZLauncherModel.shared()
        var problem: NSString?
        let state = model.checkFiles(&problem)
        switch state {
        case .missing: files = .missing
        case .damaged: files = .damaged((problem as String?) ?? "")
        case .ready: files = .ready
        @unknown default: files = .missing
        }
        accountName = HZAccountStore.shared().account()?.name
        sizeText = ""
        if state == .ready {
            DispatchQueue.global(qos: .utility).async {
                let bytes = model.resourcesSize()
                let text = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                DispatchQueue.main.async { self.sizeText = text }
            }
        }
    }

    /// The same Play as before: the game is a separate run of the app, so leave the one-shot flag and exit.
    /// (Replaced by an in-process start in M24 stage 3.)
    func play() {
        guard HZLauncherModel.shared().setStartGameFlag() else { startFailed = true; return }
        HorizonCrashReporterCleanExit()
        exit(0)
    }

    func cancelPlay() { _ = HZLauncherModel.shared().consumeStartGameFlag() }
}
