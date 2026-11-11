import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The prepared game files (the resources folder): what state they are in, importing a folder made on a computer,
/// checking them with the same test the game makes before it starts, and deleting them.
@MainActor
final class FilesController: ObservableObject {
    @Published var state: LauncherState.Files = .checking
    @Published var size: Int64 = 0
    @Published var items = 0
    @Published var busy = false
    @Published var fraction = 0.0
    @Published var current = ""
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var showAlert = false

    private var model: HZLauncherModel { HZLauncherModel.shared()! }
    var resourcesPath: String { model.resources }

    func refresh() {
        var problem: NSString?
        switch model.checkFiles(&problem) {
        case .missing: state = .missing
        case .damaged: state = .damaged((problem as String?) ?? "")
        case .ready: state = .ready
        @unknown default: state = .missing
        }
        items = Int(model.topLevelItemCount())
        let m = model
        DispatchQueue.global(qos: .utility).async {
            let bytes = Int64(clamping: m.resourcesSize())
            DispatchQueue.main.async { self.size = bytes }
        }
    }

    func check() {
        var problem: NSString?
        let s = model.checkFiles(&problem)
        refresh()
        if s == .ready {
            say("The files look good", "horizon-resources.json is present and valid, and no other top-level JSON file is empty. This is the same test the game makes before it starts.")
        } else {
            say("Problem found", (problem as String?) ?? "The files are not usable.")
        }
    }

    func importFolder(_ url: URL) {
        busy = true; fraction = 0; current = "Starting..."
        model.importFolder(at: url, completion: { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                self.refresh()
                if let error { self.say("Import failed", error.localizedDescription); Haptics.warning() }
                else { self.say("Import finished", "The game files are on the phone. Go back and press Play."); Haptics.success() }
            }
        }, progress: { [weak self] fraction, file in
            Task { @MainActor in self?.fraction = fraction; self?.current = file ?? "" }
        })
    }

    func deleteAll() {
        let fm = FileManager.default
        do { try fm.removeItem(atPath: model.resources) } catch { say("Could not delete", error.localizedDescription) }
        try? fm.createDirectory(atPath: model.resources, withIntermediateDirectories: true)
        refresh()
    }

    private func say(_ title: String, _ message: String) {
        alertTitle = title; alertMessage = message; showAlert = true
    }
}

struct GameFilesPage: View {
    @StateObject private var c = FilesController()
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2
    @State private var picking = false
    @State private var confirmDelete = false

    var body: some View {
        Page("Game files") {
            statusCard
            if c.busy { importCard }
            VStack(spacing: 12) {
                Button { Haptics.tap(); picking = true } label: {
                    Label("Import a folder", systemImage: "square.and.arrow.down").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }
                .primaryAction().tint(brand).controlSize(.large).disabled(c.busy)
                HStack(spacing: 12) {
                    Button { c.check() } label: {
                        Label("Check", systemImage: "checkmark.seal").font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .secondaryAction().disabled(c.busy)
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete", systemImage: "trash").font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .secondaryAction().tint(brand2).disabled(c.busy || c.items == 0)
                }
                Button { showInFiles() } label: {
                    Label("Show in the Files app", systemImage: "folder").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 40)
                }
                .secondaryAction()
            }
            helpCard
        }
        .onAppear { c.refresh() }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { c.importFolder(url) }
        }
        .alert(c.alertTitle, isPresented: $c.showAlert) { Button("OK", role: .cancel) {} } message: { Text(c.alertMessage) }
        .alert("Delete the game files?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { c.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the resources folder (\(ByteText.string(c.size))). Your worlds and settings are kept.")
        }
    }

    private var statusCard: some View {
        let (title, detail, tone, symbol) = words
        return VStack(spacing: 12) {
            IconTile(symbol: symbol, tone: tone, size: 56)
            Text(title).font(.system(.title3, design: .rounded).weight(.bold))
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if case .ready = c.state {
                HStack(spacing: 10) {
                    StatusPill(kind: .info, text: ByteText.string(c.size))
                    StatusPill(kind: .info, text: "\(c.items) items")
                }
            }
        }
        .padding(22).frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 32, tint: brand.opacity(0.16))
    }

    private var words: (String, String, IconTile.Tone, String) {
        switch c.state {
        case .checking: return ("Checking...", "One moment.", .neutral, "hourglass")
        case .missing: return ("No game files yet", "Import a folder prepared on a computer, or download the game from the Download page.", .warn, "tray")
        case .damaged(let why): return ("Game files need attention", why + " Import them again.", .brand2, "exclamationmark.triangle.fill")
        case .ready: return ("Game files are ready", "Everything the game needs is on this phone.", .ok, "checkmark.seal.fill")
        }
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Importing").font(.headline)
            MixBar(fraction: c.fraction, height: 12)
            Text(c.current).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 24)
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where they live").font(.headline)
            Text("Files > On My iPhone > iMC Horizon > Horizon > resources. Pick the folder that has horizon-resources.json in it, or the folder above it; the import copies it into place and checks it.")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 24)
    }

    /// The Files app can be sent to a path inside this app's Documents folder.
    private func showInFiles() {
        let root = LauncherFile.root
        if let url = URL(string: "shareddocuments://" + root) { UIApplication.shared.open(url) }
    }
}
