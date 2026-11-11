import SwiftUI
import UIKit

/// The game download, kept alive for the whole app (not per screen), so leaving the page does not lose track of a
/// run in progress. The steps and the safety rules are the Objective-C HZDownloader's; this only drives and shows it.
@MainActor
final class DownloadCenter: ObservableObject {
    static let shared = DownloadCenter()

    enum Phase { case idle, gate, looking, checking, downloading, done, failed, cancelled }

    @Published var phase: Phase = .idle
    @Published var detail = ""
    @Published var fileLine = ""
    @Published var error: String? = nil
    @Published var refusal: String? = nil
    @Published var bytesDone: UInt64 = 0
    @Published var bytesTotal: UInt64 = 0
    @Published var filesDone = 0
    @Published var filesTotal = 0
    @Published var speed: String? = nil
    @Published var timeLeft: String? = nil

    let version = "26.3"
    private var downloader: HZDownloader?
    private var rate = HZDownloadRate()
    private var model: HZLauncherModel { HZLauncherModel.shared()! }

    var busy: Bool { [.gate, .looking, .checking, .downloading].contains(phase) }
    var gameFolder: String { (model.root as NSString).appendingPathComponent("minecraft") }
    /// A file named developer-download in the Horizon folder skips the account check (for testing only).
    var overrideOn: Bool { FileManager.default.fileExists(atPath: (model.root as NSString).appendingPathComponent("developer-download")) }
    var fraction: Double { bytesTotal > 0 ? min(1, Double(bytesDone) / Double(bytesTotal)) : 0 }

    func start() {
        guard !busy else { return }
        refusal = nil
        error = nil
        if overrideOn { begin(); return }
        guard HZAccountStore.shared().account() != nil else {
            refusal = "Sign in first. Open Account and sign in with the Microsoft account that owns Minecraft: Java Edition."
            return
        }
        phase = .gate
        detail = "Asking Microsoft and Mojang that this account owns Minecraft: Java Edition."
        // A fresh answer when the services can be reached; offline, the last answer stands (HZMayDownload).
        HZAccountClient.shared().recheck { [weak self] reachable, owns, _ in
            Task { @MainActor in
                guard let self else { return }
                let now = HZAccountStore.shared().account()
                if !HZMayDownload(now != nil, now?.owns ?? false, reachable, owns) {
                    self.phase = .idle
                    self.refusal = reachable ? "This account does not own Minecraft: Java Edition, so the game cannot be downloaded."
                                             : "Could not check your account and it has not passed before. Connect to the internet and try again."
                    Haptics.warning()
                    return
                }
                self.begin()
            }
        }
    }

    private func begin() {
        let d = HZDownloader(root: gameFolder, version: version)
        downloader = d
        phase = .looking
        bytesDone = 0; bytesTotal = 0; filesDone = 0; filesTotal = 0
        speed = nil; timeLeft = nil; fileLine = ""
        UIApplication.shared.isIdleTimerDisabled = Prefs.shared.keepAwake
        rate = HZDownloadRate()
        d.start { [weak self] p in
            Task { @MainActor in self?.apply(p) }
        }
    }

    func stop() {
        detail = "Stopping..."
        downloader?.cancel()
    }

    private func apply(_ p: HZDownloadProgress) {
        // HZDownloadPhase: 0 idle, 1 looking, 2 checking, 3 downloading, 4 done, 5 failed, 6 cancelled
        switch p.phase.rawValue {
        case 1: phase = .looking; detail = p.message
        case 2: phase = .checking; detail = p.message
        case 3: phase = .downloading; detail = "Keep the app open. Stopping is safe: finished files are kept."; fileLine = p.message
        case 4: phase = .done; detail = p.message; finish(); Haptics.success()
        case 5: phase = .failed; error = p.error ?? "Unknown error."; finish(); Haptics.warning()
        case 6: phase = .cancelled; detail = p.message; finish()
        default: break
        }
        if p.bytesTotal > 0 {
            bytesDone = p.bytesDone; bytesTotal = p.bytesTotal
            filesDone = Int(p.filesDone); filesTotal = Int(p.filesTotal)
            // Speed and time left only while files are really coming in, and only once there is enough to be honest.
            if p.phase.rawValue == 3 {
                rate.noteBytes(p.bytesDone, at: ProcessInfo.processInfo.systemUptime)
                speed = rate.speedText()
                timeLeft = rate.timeLeftText(remaining: p.bytesTotal > p.bytesDone ? p.bytesTotal - p.bytesDone : 0)
            }
        }
    }

    private func finish() {
        UIApplication.shared.isIdleTimerDisabled = false
        fileLine = ""; speed = nil; timeLeft = nil
    }
}

struct DownloadPage: View {
    @ObservedObject private var d = DownloadCenter.shared
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2
    @State private var free: Int64 = 0

    var body: some View {
        Page("Download") {
            hero
            if d.phase == .downloading || d.phase == .looking || d.phase == .checking || d.bytesTotal > 0 { progressCard }
            if let why = d.refusal { notice(why) }
            actions
            infoCard
        }
        .onAppear { free = LauncherState.freeSpace(at: LauncherFile.root) }
    }

    private var title: String {
        switch d.phase {
        case .idle: return "Download Minecraft \(d.version)"
        case .gate: return "Checking your account..."
        case .looking: return "Preparing the download..."
        case .checking: return "Checking what is already here..."
        case .downloading: return "Downloading Minecraft \(d.version)"
        case .done: return "Download finished"
        case .failed: return "The download stopped"
        case .cancelled: return "Stopped"
        }
    }

    private var subtitle: String {
        switch d.phase {
        case .idle: return "The game files come straight from Mojang's servers to this phone. Your account must own Minecraft: Java Edition."
        case .failed: return (d.error ?? "") + "\n\nStart again to carry on: files that finished are kept."
        default: return d.detail
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient(colors: [brand, brand2], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 76, height: 76)
                Image(systemName: icon).font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
            }
            Text(title).font(.system(.title2, design: .rounded).weight(.bold)).multilineTextAlignment(.center)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22).frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 32, tint: brand.opacity(0.16))
    }

    private var icon: String {
        switch d.phase {
        case .done: return "checkmark"
        case .failed: return "exclamationmark"
        case .cancelled: return "pause.fill"
        case .idle: return "arrow.down"
        default: return "arrow.down.circle"
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int((d.fraction * 100).rounded())) %").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                Spacer()
                if let speed = d.speed { Text(speed).font(.subheadline.weight(.semibold)).monospacedDigit() }
            }
            MixBar(fraction: d.fraction, height: 12)
            HStack {
                Text("\(ByteText.string(Int64(clamping: d.bytesDone))) of \(ByteText.string(Int64(clamping: d.bytesTotal)))")
                Spacer()
                if let left = d.timeLeft { Text(left) }
            }
            .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            if d.filesTotal > 0 {
                Text("\(d.filesDone) of \(d.filesTotal) files").font(.footnote).foregroundStyle(.secondary)
            }
            if !d.fileLine.isEmpty {
                Text(d.fileLine).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(2)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 26)
    }

    private func notice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: "exclamationmark.triangle.fill", tone: .warn, size: 36)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22, tint: Palette.warn.opacity(0.18))
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button { Haptics.tap(); d.start() } label: {
                Text(startTitle).font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            }
            .primaryAction().tint(brand).controlSize(.large).disabled(d.busy)
            if d.phase == .downloading || d.phase == .looking || d.phase == .checking {
                Button(role: .cancel) { d.stop() } label: {
                    Text("Stop").font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                }
                .secondaryAction().tint(brand2)
            }
        }
    }

    private var startTitle: String {
        switch d.phase {
        case .done: return "Check again"
        case .failed: return "Try again"
        case .cancelled: return "Continue"
        case .gate: return "Checking..."
        case .looking, .checking, .downloading: return "Downloading..."
        case .idle: return "Download"
        }
    }

    private var infoCard: some View {
        GlassGroup {
            RowLabel(symbol: "arrow.down.to.line.circle.fill", tone: .brand, title: "Size", detail: "About 673 MB for the game itself.", chevron: false)
            Sep()
            RowLabel(symbol: "externaldrive.fill", tone: free > 2_500_000_000 ? .ok : .warn, title: "Free space",
                     detail: "\(ByteText.string(free)) free. The download needs about 2.5 GB while it works.", chevron: false)
            Sep()
            RowLabel(symbol: "wifi", tone: .brand2, title: "Connection",
                     detail: "Use Wi-Fi. A stopped download carries on where it left off.", chevron: false)
            Sep()
            RowLabel(symbol: "checkmark.shield.fill", tone: .brand, title: "Checked on arrival",
                     detail: "Every file is verified against the size and SHA-1 Mojang lists before it is kept.", chevron: false)
        }
    }
}
