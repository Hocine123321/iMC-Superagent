import SwiftUI
import UIKit

/// Diagnostics: a check-up the person runs and reads, and the logs. Nothing here changes the game or sends anything; the
/// network checks make small requests to Microsoft, Mojang and the Horizon registry, the same servers the app already uses.
struct DiagnosticsPage: View {
    enum Mode: String, CaseIterable, Identifiable { case checkup = "Check-up", logs = "Logs"; var id: String { rawValue } }

    @State private var mode: Mode
    @StateObject private var runner = DiagnosticsRunner()
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2
    @State private var sharing: ShareItem? = nil
    @State private var shareFiles: ShareFiles? = nil
    @State private var confirmClearCaches = false
    @State private var confirmClearLogs = false
    @State private var note: String? = nil
    @State private var probesOn = DiagFiles.exists(DiagFiles.path("probes-ad.txt"))

    struct ShareFiles: Identifiable { let id = UUID(); let urls: [URL] }

    init(start: Mode = .checkup) { _mode = State(initialValue: start) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 8)
            if mode == .checkup { checkup } else { LogsView() }
        }
        .screenBackground()
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mode == .checkup && runner.finished != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { if let u = runner.reportFile() { sharing = ShareItem(url: u) } } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share the report")
                }
            }
        }
        .sheet(item: $sharing) { ShareSheet(items: [$0.url]).ignoresSafeArea() }
        .sheet(item: $shareFiles) { ShareSheet(items: $0.urls).ignoresSafeArea() }
        .alert("Clear caches?", isPresented: $confirmClearCaches) {
            Button("Clear", role: .destructive) { clearCaches() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Removes the Marketplace list, unfinished Marketplace downloads and saved Minecraft heads. They are fetched again when needed. Your files, worlds and settings are kept.") }
        .alert("Delete the logs?", isPresented: $confirmClearLogs) {
            Button("Delete", role: .destructive) { clearLogs() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Removes crash reports, the game log, the session log and the start-up report. They are written again the next time the app runs.") }
    }

    // MARK: check-up

    private var checkup: some View {
        ScrollView {
            GlassStack(spacing: 18) {
                VStack(spacing: 16) {
                    summaryCard
                    if !advice.isEmpty { adviceCard }
                    ForEach(groups, id: \.self) { g in
                        SectionLabel(g)
                        GlassGroup {
                            let items = runner.results.filter { $0.group == g }
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, r in
                                if i > 0 { Sep(inset: 54) }
                                resultRow(r)
                            }
                        }
                    }
                    tools
                }
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var groups: [String] {
        var seen: [String] = []
        for r in runner.results where !seen.contains(r.group) { seen.append(r.group) }
        return seen
    }

    private var advice: [CheckResult] { runner.results.filter { ($0.status == .warn || $0.status == .fail) && $0.advice != nil } }

    private var worst: CheckStatus {
        if runner.problems > 0 { return .fail }
        if runner.warnings > 0 { return .warn }
        return .pass
    }

    private var summaryCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient(colors: [brand, brand2], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 72, height: 72)
                Image(systemName: summarySymbol).font(.system(size: 32, weight: .semibold)).foregroundStyle(.white)
            }
            Text(summaryTitle).font(.system(.title2, design: .rounded).weight(.bold)).multilineTextAlignment(.center)
            Text(summaryDetail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if runner.running {
                MixBar(fraction: runner.total == 0 ? 0 : Double(runner.done) / Double(runner.total), height: 10)
                Text("\(runner.done) of \(runner.total) checks").font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            } else if runner.finished != nil {
                HStack(spacing: 8) {
                    StatusPill(kind: .ok, text: "\(runner.passes) fine")
                    StatusPill(kind: .warn, text: "\(runner.warnings) to look at")
                    StatusPill(kind: .bad, text: "\(runner.problems) problem\(runner.problems == 1 ? "" : "s")")
                }
            }
            Button { Haptics.tap(); runner.run() } label: {
                Label(runner.finished == nil ? "Run the check-up" : "Run again", systemImage: "stethoscope").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .primaryAction().tint(brand).controlSize(.large).disabled(runner.running)
        }
        .padding(22).frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 32, tint: brand.opacity(0.16))
    }

    private var summarySymbol: String {
        if runner.running { return "waveform.path.ecg" }
        if runner.finished == nil { return "stethoscope" }
        switch worst { case .fail: return "exclamationmark.triangle.fill"; case .warn: return "exclamationmark"; default: return "checkmark" }
    }

    private var summaryTitle: String {
        if runner.running { return "Checking..." }
        if runner.finished == nil { return "Check how this phone is doing" }
        switch worst {
        case .fail: return "\(runner.problems) problem\(runner.problems == 1 ? "" : "s") found"
        case .warn: return "\(runner.warnings) thing\(runner.warnings == 1 ? "" : "s") to look at"
        default: return "All good"
        }
    }

    private var summaryDetail: String {
        if runner.running { return "Reading the phone, the files and the connection." }
        if let d = runner.finished { return "Finished \(DiagFiles.ago(d)). Tap a result's advice to act on it, or share the report." }
        return "Checks the phone, memory, storage, game files, network, account, settings and how the last run went. Nothing is changed. The network checks make small requests to Microsoft, Mojang and the Horizon registry."
    }

    private var adviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What to do", systemImage: "lightbulb.fill").font(.headline)
            ForEach(advice) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title).font(.subheadline.weight(.semibold))
                    Text(r.advice ?? "").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 24, tint: Palette.warn.opacity(0.16))
    }

    private func resultRow(_ r: CheckResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon(r.status).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.title).font(.body.weight(.semibold))
                if r.status == .pending { Text("Waiting").font(.footnote).foregroundStyle(.tertiary) }
                else if r.status == .running { Text("Checking...").font(.footnote).foregroundStyle(.secondary) }
                else { Text(r.detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                if let a = r.advice, r.status == .warn || r.status == .fail {
                    Text(a).font(.footnote.weight(.medium)).foregroundStyle(r.status == .fail ? brand2 : Palette.warn).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func statusIcon(_ s: CheckStatus) -> some View {
        switch s {
        case .pass: Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Palette.ok)
        case .warn: Image(systemName: "exclamationmark.triangle.fill").font(.title3).foregroundStyle(Palette.warn)
        case .fail: Image(systemName: "xmark.octagon.fill").font(.title3).foregroundStyle(brand2)
        case .info: Image(systemName: "info.circle.fill").font(.title3).foregroundStyle(brand)
        case .running: ProgressView()
        case .pending: Image(systemName: "circle").font(.title3).foregroundStyle(.tertiary)
        }
    }

    // MARK: tools

    private var tools: some View {
        VStack(spacing: 16) {
            SectionLabel("Tools")
            GlassGroup {
                Button { shareAll() } label: { RowLabel(symbol: "square.and.arrow.up.fill", title: "Share all diagnostic files", detail: "Crash reports, logs, the session log and the start-up report, as files.") }
                    .buttonStyle(.plain)
                Sep()
                ToggleRow(symbol: "testtube.2", tone: .brand2, title: "Run the JIT probes on the next start",
                          detail: "Tries two ways of getting executable memory (MAP_JIT) once per start and records the answer. Needs JIT enabled for the app from a debugger tool first.",
                          isOn: Binding(get: { probesOn }, set: { setProbes($0) }))
                Sep()
                Button { try? FileManager.default.removeItem(atPath: DiagFiles.path("probe-state.txt")); note = "Probe history cleared: the probes run again on the next start." } label: {
                    RowLabel(symbol: "arrow.counterclockwise", title: "Forget earlier probe results", detail: "So the probes can run again.", chevron: false)
                }.buttonStyle(.plain)
                Sep()
                Button { confirmClearCaches = true } label: { RowLabel(symbol: "trash.slash.fill", title: "Clear caches", detail: "Marketplace list, unfinished downloads, saved heads.", chevron: false) }.buttonStyle(.plain)
                Sep()
                Button { confirmClearLogs = true } label: { RowLabel(symbol: "trash.fill", tone: .brand2, title: "Delete the logs", detail: "Crash reports, game log, session log.", chevron: false) }.buttonStyle(.plain)
            }
            if let note { Text(note).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
    }

    private func shareAll() {
        let urls = HZLauncherModel.shared()!.diagnosticFiles() ?? []
        if urls.isEmpty { note = "There are no diagnostic files yet."; return }
        shareFiles = ShareFiles(urls: urls)
    }

    private func setProbes(_ on: Bool) {
        let p = DiagFiles.path("probes-ad.txt")
        if on { try? "".write(toFile: p, atomically: true, encoding: .utf8) } else { try? FileManager.default.removeItem(atPath: p) }
        probesOn = on
    }

    private func clearCaches() {
        var freed: UInt64 = 0
        for sub in ["marketplace"] {
            let p = DiagFiles.path(sub)
            freed += DiagFiles.size(of: p)
            try? FileManager.default.removeItem(atPath: p)
        }
        let staging = HZMarketInstaller(home: DiagFiles.home).stagingDirectory()
        freed += DiagFiles.size(of: staging); try? FileManager.default.removeItem(atPath: staging)
        SkinService.forget()
        note = "Caches cleared (\(DiagFiles.bytes(freed)))."
    }

    private func clearLogs() {
        let fm = FileManager.default
        for p in [DiagFiles.path("crash.txt"), DiagFiles.path("crash-previous.txt"), DiagFiles.path("session-log.csv"), DiagFiles.path("session-log-previous.csv"),
                  DiagFiles.path("diagnostics.txt"), DiagFiles.path("home", "logs", "latest.log"), DiagFiles.path("unclean-ends")] { try? fm.removeItem(atPath: p) }
        let dir = DiagFiles.path("home", "crash-reports")
        if let names = try? fm.contentsOfDirectory(atPath: dir) { for n in names { try? fm.removeItem(atPath: (dir as NSString).appendingPathComponent(n)) } }
        note = "Logs deleted."
    }
}
