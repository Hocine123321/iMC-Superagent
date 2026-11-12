import SwiftUI
import Charts

/// The logs the app and the game leave on the phone, read in the launcher: the crash report with a plain-language reading,
/// the game log with a filter, the memory and heat timeline of the last session, and the start-up report.
struct LogsView: View {
    enum Source: String, CaseIterable, Identifiable {
        case crash = "Crash report", game = "Game log", session = "Session", startup = "Start-up"
        var id: String { rawValue }
    }
    enum Level: String, CaseIterable, Identifiable { case all = "All", warnings = "Warnings", errors = "Errors"; var id: String { rawValue } }

    @State private var source: Source = .crash
    @State private var level: Level = .all
    @State private var query = ""
    @State private var text = ""
    @State private var crash: CrashInfo? = nil
    @State private var stats: SessionStats? = nil
    @State private var path: String? = nil
    @State private var sharing: ShareItem? = nil
    @State private var confirmDelete = false
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GlassStack(spacing: 16) {
                    LazyVStack(spacing: 14) {
                        controls
                        switch source {
                        case .crash: crashHeader
                        case .session: sessionHeader
                        default: EmptyView()
                        }
                        if source != .session || stats == nil { logBody(text) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 40)
                }
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .bottomTrailing) {
                if source == .game || source == .startup {
                    Button { withAnimation { proxy.scrollTo("end", anchor: .bottom) } } label: { Image(systemName: "arrow.down.to.line").font(.headline).frame(width: 44, height: 44) }
                        .secondaryAction().circleShape().padding(18)
                        .accessibilityLabel("Jump to the end")
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: source) { _ in reload() }
        .sheet(item: $sharing) { ShareSheet(items: [$0.url]).ignoresSafeArea() }
        .alert("Delete this file?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { if let p = path { try? FileManager.default.removeItem(atPath: p); reload() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("It is written again the next time the app runs.") }
    }

    // MARK: pieces

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Log", selection: $source) { ForEach(Source.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            if source == .game {
                Picker("Level", selection: $level) { ForEach(Level.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search the log", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
                }
                .padding(.horizontal, 14).padding(.vertical, 10).glassCapsule()
            }
            HStack(spacing: 10) {
                Button { if let p = path { sharing = ShareItem(url: URL(fileURLWithPath: p)) } } label: { Label("Share", systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36) }
                    .secondaryAction().disabled(path == nil)
                Button { UIPasteboard.general.string = text; Haptics.success() } label: { Label("Copy", systemImage: "doc.on.doc").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36) }
                    .secondaryAction().disabled(text.isEmpty)
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash").font(.subheadline.weight(.semibold)).frame(width: 36, height: 36) }
                    .secondaryAction().circleShape().tint(brand2).disabled(path == nil)
                    .accessibilityLabel("Delete this file")
            }
        }
    }

    @ViewBuilder private func logBody(_ raw: String) -> some View {
        let shown = filtered(raw)
        if shown.isEmpty {
            Text(emptyText).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24).frame(maxWidth: .infinity)
        } else {
            LongText(text: shown).padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard(cornerRadius: 20)
        }
    }

    private var emptyText: String {
        switch source {
        case .crash: return "No crash report. The game has not crashed since the files were last cleared."
        case .game: return query.isEmpty && level == .all ? "No game log yet. It appears after the game has run once." : "No lines match."
        case .session: return "No session log yet. It is written while the app runs."
        case .startup: return "No start-up report yet."
        }
    }

    @ViewBuilder private var crashHeader: some View {
        if let c = crash {
            VStack(alignment: .leading, spacing: 8) {
                Label(c.headline, systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(brand2)
                Text(DiagFiles.ago(c.date)).font(.footnote).foregroundStyle(.tertiary)
                Text(c.detail).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Text(c.advice).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 22, tint: brand2.opacity(0.18))
        }
    }

    @ViewBuilder private var sessionHeader: some View {
        if let s = stats {
            VStack(alignment: .leading, spacing: 14) {
                Text("Last session").font(.headline)
                HStack {
                    stat("Length", "\(Int(s.duration / 60)) min")
                    stat("Peak use", s.peakFootprint.map { "\(Int($0)) MB" } ?? "-")
                    stat("Least room", s.minAvailable.map { "\(Int($0)) MB" } ?? "-")
                }
                let step = max(1, s.samples.count / 300)
                let points = s.samples.enumerated().filter { $0.offset % step == 0 }.map { $0.element }
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                        if let f = p.footprint { LineMark(x: .value("Minutes", p.t / 60), y: .value("MB", f), series: .value("Series", "In use")).foregroundStyle(by: .value("Series", "In use")) }
                        if let a = p.available, a > 0 { LineMark(x: .value("Minutes", p.t / 60), y: .value("MB", a), series: .value("Series", "Room left")).foregroundStyle(by: .value("Series", "Room left")) }
                    }
                }
                .chartForegroundStyleScale(["In use": brand, "Room left": brand2])
                .chartXAxisLabel("minutes")
                .chartYAxisLabel("MB")
                .frame(height: 180)
                Text(thermalLine(s)).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 22)
        } else {
            Text(emptyText).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24).frame(maxWidth: .infinity)
        }
    }

    private func thermalLine(_ s: SessionStats) -> String {
        let names = ["normal", "warm", "hot", "very hot"]
        return "Hottest: \(names[min(max(s.maxThermal, 0), 3)])." + (s.lowPowerSeen ? " Low Power Mode was on at some point." : "")
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(label).font(.footnote).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: data

    private func filtered(_ raw: String) -> String {
        guard source == .game, level != .all || !query.isEmpty else { return raw }
        let q = query.lowercased()
        return raw.components(separatedBy: "\n").filter { line in
            let l = line.lowercased()
            if level == .errors && !(l.contains("error") || l.contains("panick") || l.contains("fatal")) { return false }
            if level == .warnings && !(l.contains("warn") || l.contains("error") || l.contains("panick") || l.contains("fatal")) { return false }
            return q.isEmpty || l.contains(q)
        }.joined(separator: "\n")
    }

    private func reload() {
        crash = nil; stats = nil; text = ""; path = nil
        switch source {
        case .crash:
            if let c = CrashFiles.newest() {
                crash = c; text = c.text; path = c.url.path
                LauncherFile.set("crashSeen", String(Int(c.date.timeIntervalSince1970)))   // the Play tab's banner goes away
            }
        case .game:
            let p = DiagFiles.path("home", "logs", "latest.log")
            if let t = DiagFiles.tail(p) { text = t; path = p }
        case .session:
            let p = DiagFiles.path("session-log.csv")
            stats = SessionStats.read(path: p)
            if stats != nil { path = p }
        case .startup:
            let p = DiagFiles.path("diagnostics.txt")
            if let t = DiagFiles.text(p) { text = t; path = p }
        }
    }
}
