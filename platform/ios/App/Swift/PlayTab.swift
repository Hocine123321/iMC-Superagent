import SwiftUI

/// The first tab: what is installed, and one big Play button.
struct PlayTab: View {
    @ObservedObject var state: LauncherState
    var openDownload: () -> Void
    var openFiles: () -> Void
    var openAccount: () -> Void

    @State private var confirmPlay = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                heroCard
                shortcuts
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Backdrop())
        .alert("Starting the game", isPresented: $confirmPlay) {
            Button("Close app") { state.play() }
            Button("Cancel", role: .cancel) { state.cancelPlay() }
        } message: {
            Text("iMC Horizon will close now. Open it again and the game starts.")
        }
        .alert("Could not start", isPresented: $state.startFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The launcher could not write its start flag in the Horizon folder.")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MINECRAFT 26.3  ·  JAVA")
                    .font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
                Text("iMC Horizon").font(.largeTitle.bold())
            }
            Spacer()
            Button(action: openAccount) {
                Image(systemName: state.accountName == nil ? "person.crop.circle" : "person.crop.circle.fill")
                    .font(.title2).frame(width: 44, height: 44)
            }
            .secondaryAction()
            .circleShape()
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
                Button { confirmPlay = true } label: {
                    Label("Play", systemImage: "play.fill").font(.title2.weight(.bold)).frame(maxWidth: .infinity, minHeight: 56)
                }
                .primaryAction()
                .controlSize(.large)
                if let name = state.accountName {
                    Text("Playing as \(name)").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Not signed in: the game starts offline.").font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Button(action: openFiles) {
                    Label("Import game files", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, minHeight: 50)
                }
                .primaryAction()
                .controlSize(.large)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var shortcuts: some View {
        VStack(spacing: 12) {
            shortcut("Download from Mojang", "arrow.down.circle", "Get the game files directly on this phone.", openDownload)
            shortcut("Game files", "folder", "Import or check the folder you prepared on a computer.", openFiles)
        }
    }

    private func shortcut(_ title: String, _ symbol: String, _ sub: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title3).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(sub).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(16).frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 22)
    }

    private var dotColor: Color {
        switch state.files {
        case .ready: return Look.accent
        case .damaged: return Look.danger
        case .missing: return Look.warning
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
        case .missing: return "Download them from Mojang, or import a folder you prepared on a computer. Preparing the files on this phone is not available yet."
        case .damaged(let why): return why + " Import them again."
        case .ready: return state.sizeText.isEmpty ? "Checking the size of the game files..." : "Game files \(state.sizeText) on this phone."
        }
    }
}
