import SwiftUI

enum PlayRoute: Hashable { case download, files, account, diagnostics }

/// The first tab: the state of the game, one big Play button, the way to the files, and what the phone has left.
struct PlayTab: View {
    @ObservedObject var state: LauncherState
    @ObservedObject private var prefs = Prefs.shared
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2
    var open: (PlayRoute) -> Void

    @State private var confirmPlay = false

    var body: some View {
        ScrollView {
            GlassStack(spacing: 18) {
                VStack(spacing: 16) {
                    header
                    heroCard
                    if state.hasCrash { crashCard }
                    HStack(spacing: 14) {
                        tile("Download", "arrow.down.circle.fill", "Get the game files from Mojang.", .brand) { open(.download) }
                        tile("Game files", "folder.fill", "Import or check a prepared folder.", .brand2) { open(.files) }
                    }
                    storageCard
                    footer
                }
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .alert("Start the game?", isPresented: $confirmPlay) {
            Button("Close app and play") { state.play() }
            Button("Cancel", role: .cancel) { state.cancelPlay() }
        } message: {
            Text("iMC Horizon closes now. Open it again and the game starts.")
        }
        .alert("Could not start", isPresented: $state.startFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The launcher could not write its start flag in the Horizon folder.")
        }
    }

    // MARK: pieces

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            BrandMark().frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("MINECRAFT 26.3  ·  JAVA")
                    .font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
                Text("iMC Horizon").font(.system(.largeTitle, design: .rounded).weight(.bold))
            }
            Spacer(minLength: 0)
            Button { Haptics.tap(); open(.account) } label: {
                Image(systemName: state.accountName == nil ? "person.crop.circle" : "person.crop.circle.fill")
                    .font(.title2).frame(width: 46, height: 46)
            }
            .secondaryAction().circleShape()
            .accessibilityLabel(state.accountName.map { "Account, signed in as \($0)" } ?? "Account, not signed in")
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Circle().fill(dotColor).frame(width: 12, height: 12)
                Text(title).font(.title3.weight(.semibold))
            }
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if state.isReady {
                Button { Haptics.tap(); tapPlay() } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.title2.weight(.bold)).frame(maxWidth: .infinity, minHeight: 58)
                }
                .primaryAction().tint(brand).controlSize(.large)
                Text(state.accountName.map { "Playing as \($0)" } ?? "Not signed in: the game starts offline.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Button { Haptics.tap(); open(.files) } label: {
                    Label("Import game files", systemImage: "square.and.arrow.down")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }
                .primaryAction().tint(brand).controlSize(.large)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 32, tint: brand.opacity(0.22))
    }

    private var crashCard: some View {
        Button { Haptics.tap(); open(.diagnostics) } label: {
            HStack(spacing: 14) {
                IconTile(symbol: "exclamationmark.triangle.fill", tone: .brand2, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("The game stopped unexpectedly").font(.body.weight(.semibold))
                    Text("There is a crash report. Open Diagnostics to read it or run a check.")
                        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(16).frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 24, tint: brand2.opacity(0.22), interactive: true)
    }

    private func tile(_ title: String, _ symbol: String, _ detail: String, _ tone: IconTile.Tone, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            VStack(alignment: .leading, spacing: 12) {
                IconTile(symbol: symbol, tone: tone, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 26, interactive: true)
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("On this phone").font(.headline)
            HStack(alignment: .top) {
                stat("Game files", state.isReady ? ByteText.string(state.resourceBytes) : "None")
                Divider().frame(height: 36)
                stat("Free space", ByteText.string(state.freeBytes))
            }
            // Enough room to download Minecraft and prepare it (the download plan says about 673 MB, and the
            // download needs room for the old and new copy while it works).
            let need: Int64 = 2_500_000_000
            if !state.isReady {
                MixBar(fraction: min(1, Double(state.freeBytes) / Double(need)))
                Text(state.freeBytes >= need ? "Enough room to download the game."
                                             : "Downloading needs about \(ByteText.string(need)) free.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 26)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold))
            Text(label).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        return Text("Launcher \(version)  ·  Built on Horizon  ·  Not affiliated with Mojang or Microsoft")
            .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center).padding(.top, 4)
    }

    private func tapPlay() {
        if prefs.confirmPlay { confirmPlay = true } else { state.play() }
    }

    // MARK: words

    private var dotColor: Color {
        switch state.files {
        case .ready: return Palette.ok
        case .damaged: return brand2
        case .missing: return Palette.warn
        case .checking: return .gray
        }
    }
    private var title: String {
        switch state.files {
        case .checking: return "Checking the game files"
        case .missing: return "No game files yet"
        case .damaged: return "Game files need attention"
        case .ready: return "Ready to play"
        }
    }
    private var detail: String {
        switch state.files {
        case .checking: return "One moment."
        case .missing: return "Download them from Mojang, or import a folder you prepared on a computer."
        case .damaged(let why): return why + " Import them again."
        case .ready: return "Everything the game needs is on this phone."
        }
    }
}
