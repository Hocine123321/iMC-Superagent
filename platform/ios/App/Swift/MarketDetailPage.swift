import SwiftUI
import UIKit

/// One project's page: what it is, the install button with its progress, and what the app checks. Horizon's
/// registry projects and Modrinth resource packs share it; the Objective-C installer and fetcher do the work.
@MainActor
final class MarketDetailController: ObservableObject {
    let row: MarketRow
    let index: HZMarketIndex?
    let game = "26.3"

    private(set) var project: HZMarketProject?
    private(set) var version: HZMarketVersion?
    private(set) var mproject: HZModrinthProject?
    private(set) var mversion: HZModrinthVersion?

    @Published var looking = false
    @Published var versionProblem: String? = nil
    @Published var busy = false
    @Published var progress = 0.0
    @Published var status: String? = nil
    @Published var statusIsError = false
    @Published var installedVersion: String? = nil
    @Published var modEnabled = false

    private var fetcher: HZMarketFetcher?
    private var model: HZLauncherModel { HZLauncherModel.shared()! }
    private func installer() -> HZMarketInstaller { HZMarketInstaller(home: model.home) }

    init(row: MarketRow, index: HZMarketIndex?) {
        self.row = row
        self.index = index
        switch row.payload {
        case .horizon(let p):
            project = p
            if let index { version = index.installableVersion(of: p, game: game) }
        case .modrinth(let p):
            mproject = p
            looking = true
        }
        readInstalled()
    }

    func onAppear() {
        guard let mp = mproject, mversion == nil, versionProblem == nil else { return }
        looking = true
        HZModrinthClient().newestVersion(of: mp) { [weak self] v, err in
            Task { @MainActor in
                guard let self else { return }
                self.looking = false; self.mversion = v; self.versionProblem = err
                self.objectWillChange.send()
            }
        }
    }

    func onDisappear() { if busy { fetcher?.cancel() } }   // leaving the page stops a download in progress

    // MARK: facts

    var title: String { project?.name ?? mproject?.title ?? row.title }
    var byline: String {
        if let p = project { return p.authors.isEmpty ? "Horizon registry" : "by " + p.authors.joined(separator: ", ") }
        if let a = mproject?.author, !a.isEmpty { return "by " + a }
        return "Modrinth"
    }
    var available: String? {
        if let v = version { return v.version }
        if let v = mversion { return v.number.isEmpty ? v.versionId : v.number }
        return nil
    }
    var size: UInt64 { version?.file.size ?? mversion?.file.size ?? 0 }

    var refusal: String? {
        if let p = project {
            guard let v = version, let index else { return "No version of this project for Minecraft \(game) is available." }
            return HZMarketInstaller.refusal(for: p, version: v, index: index)
        }
        if looking { return "Looking up the newest version..." }
        return mversion != nil ? nil : (versionProblem ?? "No version of this pack can be installed.")
    }

    var explanation: String {
        guard let p = project else { return "Choose it in the game's resource pack list." }
        switch p.kind {
        case "mod": return modEnabled ? "Installed and turned on. Restart the game to see it." : "Installed, but turned off. Turn it on in the game, under Mods."
        case "shader": return "Choose it in the game's video settings. Shaders have not been tested on a phone."
        default: return "Choose it in the game's resource pack list."
        }
    }

    var confirmText: String {
        if let p = project {
            return p.kind == "mod" ? "Mods change the game. It is checked against the registry's fingerprint, then turned on."
                                   : "The file is checked against the registry's fingerprint before it is installed."
        }
        return "This pack comes from Modrinth, not from Horizon's reviewed registry. The app checks the file against the fingerprint Modrinth lists and that it is a plain resource pack, but it does not review the pack."
    }

    var buttonTitle: String {
        guard let have = installedVersion else { return refusal == nil && available != nil ? "Install" : "Can't install" }
        if have == available { return "Installed" }
        if refusal == nil, let a = available { return "Update to \(a)" }
        return "Installed"
    }
    var canInstall: Bool { refusal == nil && available != nil && !busy && installedVersion != available }

    func readInstalled() {
        let inst = installer()
        if let p = project {
            installedVersion = inst.installedEntry(project: p.projectId)?.version
            modEnabled = p.kind == "mod" && inst.isModEnabled(p.projectId)
        } else if let mp = mproject {
            installedVersion = inst.installedEntry(modrinth: mp.projectId)?.version
        }
    }

    // MARK: actions

    func install() {
        guard canInstall else { return }
        let need = size * 2 + (10 << 20)
        let free = LauncherState.freeSpace(at: LauncherFile.root)
        if free > 0 && UInt64(free) < need {
            fail("Not enough space. This needs about \(ByteText.string(Int64(need))) free."); return
        }
        busy = true; progress = 0; status = "Downloading..."; statusIsError = false
        let f = HZMarketFetcher()
        fetcher = f
        let staging = installer().stagingDirectory()
        let onProgress: (Double) -> Void = { [weak self] x in Task { @MainActor in self?.progress = x } }
        let onDone: (String?, String?) -> Void = { [weak self] path, error in
            Task { @MainActor in
                guard let self else { return }
                guard let path else { self.fetcher = nil; self.busy = false; self.fail(error ?? "The download failed."); return }
                self.status = "Checking the file..."
                // Hashing and moving are off the main thread; a 600 KB file is quick but a 60 MB one is not.
                let project = self.project, version = self.version, index = self.index
                let mproject = self.mproject, mversion = self.mversion
                let home: String = HZLauncherModel.shared()!.home
                DispatchQueue.global(qos: .userInitiated).async {
                    let inst = HZMarketInstaller(home: home)
                    var problem: String?
                    if let project, let version, let index {
                        problem = inst.placeDownloaded(path, project: project, version: version, index: index)
                    } else if let mproject, let mversion {
                        problem = inst.placeModrinthDownloaded(path, project: mproject, version: mversion)
                    } else {
                        problem = "There is nothing to install."
                    }
                    DispatchQueue.main.async {
                        self.fetcher = nil; self.busy = false
                        self.readInstalled()
                        if let problem { self.fail(problem) } else { self.status = nil; Haptics.success() }
                    }
                }
            }
        }
        if let v = version {
            f.fetch(v.file, stagingDir: staging, progress: onProgress, done: onDone)
        } else if let v = mversion {
            f.fetchURL(v.file.url, size: v.file.size, stagingDir: staging, redirectHosts: ["cdn.modrinth.com"], progress: onProgress, done: onDone)
        }
    }

    func remove() {
        let inst = installer()
        var problem: String?
        if let p = project { problem = inst.removeProject(p.projectId) }
        else if let mp = mproject { problem = inst.removeModrinth(mp.projectId) }
        readInstalled()
        if let problem { fail(problem) } else { status = nil }
    }

    func setModEnabled(_ on: Bool) {
        guard let p = project else { return }
        if let problem = installer().setMod(p.projectId, enabled: on) { fail(problem) }
        readInstalled()
    }

    private func fail(_ message: String) {
        status = message; statusIsError = true; Haptics.warning()
    }
}

// MARK: - The page

struct MarketDetailPage: View {
    @StateObject private var c: MarketDetailController
    @ObservedObject private var prefs = Prefs.shared
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2
    @State private var confirmInstall = false
    @State private var confirmRemove = false

    init(row: MarketRow, index: HZMarketIndex?) {
        _c = StateObject(wrappedValue: MarketDetailController(row: row, index: index))
    }

    var body: some View {
        Page("") {
            header
            actionCard
            if c.project?.kind == "mod" && c.installedVersion != nil {
                GlassGroup {
                    ToggleRow(symbol: "power", tone: .brand2, title: "Turned on", detail: "Mods change the game. Restart the game after changing this.",
                              isOn: Binding(get: { c.modEnabled }, set: { c.setModEnabled($0) }))
                }
            }
            if let p = c.project { horizonDetails(p) } else if let mp = c.mproject { modrinthDetails(mp) }
        }
        .onAppear { c.onAppear(); c.readInstalled() }
        .onDisappear { c.onDisappear() }
        .alert("Install \(c.title)?", isPresented: $confirmInstall) {
            Button("Install") { c.install() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(c.confirmText + (c.size > 0 ? "\n\nThe download is \(ByteText.string(Int64(clamping: c.size)))." : ""))
        }
        .alert("Remove \(c.title)?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { c.remove() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The file is deleted from the Horizon folder.") }
    }

    // MARK: header and action

    private var header: some View {
        HStack(spacing: 16) {
            ProjectIcon(kind: c.row.kind, url: c.row.iconURL, size: 84)
            VStack(alignment: .leading, spacing: 5) {
                Text(c.title).font(.system(.title2, design: .rounded).weight(.bold)).fixedSize(horizontal: false, vertical: true)
                Text(c.byline).font(.subheadline).foregroundStyle(.secondary)
                Text("\(MarketKind.name(c.row.kind))  ·  \(c.row.source)").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 28, tint: brand.opacity(0.14))
    }

    private var actionCard: some View {
        VStack(spacing: 12) {
            Button {
                Haptics.tap()
                if prefs.confirmInstalls { confirmInstall = true } else { c.install() }
            } label: {
                Label(c.buttonTitle, systemImage: c.installedVersion != nil && !c.canInstall ? "checkmark.circle.fill" : (c.refusal == nil ? "arrow.down.circle.fill" : "nosign"))
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            }
            .primaryAction().tint(brand).controlSize(.large).disabled(!c.canInstall)
            if c.busy { MixBar(fraction: c.progress, height: 10) }
            if c.installedVersion != nil {
                Button(role: .destructive) { confirmRemove = true } label: {
                    Label("Remove", systemImage: "trash").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 42)
                }
                .secondaryAction().tint(brand2).disabled(c.busy)
            }
            Text(statusLine).font(.footnote).foregroundStyle(statusColour).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusLine: String {
        if let s = c.status { return s }
        if c.installedVersion != nil && c.installedVersion == c.available { return c.explanation }
        if let have = c.installedVersion, c.canInstall { return "Installed: \(have)." }
        if c.canInstall { return c.explanation }
        return c.refusal ?? "There is nothing to install."
    }

    private var statusColour: Color {
        if c.statusIsError { return brand2 }
        if c.refusal != nil && c.installedVersion == nil && c.status == nil { return Palette.warn }
        return .secondary
    }

    // MARK: Horizon

    private func horizonDetails(_ p: HZMarketProject) -> some View {
        let v = c.version
        let revoked: HZMarketRevoked? = {
            guard let index = c.index else { return nil }
            if v != nil { return nil }
            return index.revocation(for: p.projectId, sha256: nil) ?? index.revocation(for: p.projectId, sha256: p.versions.first?.file.sha256)
        }()
        return VStack(spacing: 16) {
            if !p.summary.isEmpty { textCard(nil, p.summary, big: true) }
            if p.support.rawValue == 1 {
                notice("This is a native mod. It changes the game's Rust source before the game is compiled, so it needs a desktop build and cannot be added on a phone.", warn: true)
            }
            if let r = revoked {
                notice("Taken down by the registry" + (r.date.isEmpty ? "" : " on " + r.date) + ": " + r.reason, warn: false)
            }
            if !p.screenshots.isEmpty { gallery(p.screenshots) }
            SectionLabel("Details")
            GlassGroup {
                fact("Type", MarketKind.name(p.kind))
                Sep(inset: 16); fact("Licence", p.license)
                if !p.categories.isEmpty { Sep(inset: 16); fact("Categories", p.categories.joined(separator: ", ")) }
                if let v { Sep(inset: 16); fact("Version", "\(v.version) for Minecraft \(v.game), \(ByteText.string(Int64(clamping: v.file.size)))") }
                Sep(inset: 16); fact("Popularity", "\(p.downloads) downloads, \(p.stars) stars")
                Sep(inset: 16); fact("Signed", (p.key ?? "").isEmpty ? "No. The registry's fingerprint of the file is checked." : "Yes. This app cannot check signatures yet, so it will not install it.")
                Sep(inset: 16); fact("Source", p.source)
            }
            textCard("What the app checks", "The file must come from the registry's release address, match the size and SHA-256 the registry lists, not be taken down, and be a ZIP. The game checks the content itself when it reads it. The app does not review what is inside.")
            if !p.details.isEmpty { textCard("Description", p.details) }
            if let log = v?.changelog, !log.isEmpty { textCard("Changelog", log) }
        }
    }

    // MARK: Modrinth

    private func modrinthDetails(_ p: HZModrinthProject) -> some View {
        VStack(spacing: 16) {
            if !p.summary.isEmpty { textCard(nil, p.summary, big: true) }
            SectionLabel("Details")
            GlassGroup {
                fact("Type", "Resource pack")
                Sep(inset: 16); fact("Source", "Modrinth")
                if !p.license.isEmpty { Sep(inset: 16); fact("Licence", p.license) }
                if p.downloads > 0 { Sep(inset: 16); fact("Popularity", "\(p.downloads) downloads") }
                if let v = c.mversion {
                    Sep(inset: 16); fact("Version", "\(v.number) for Minecraft 26.3, \(ByteText.string(Int64(clamping: v.file.size)))")
                    Sep(inset: 16); fact("File", v.file.name)
                } else if c.looking {
                    Sep(inset: 16); fact("Version", "Looking up the newest version...")
                } else if let problem = c.versionProblem {
                    Sep(inset: 16); fact("Version", problem)
                }
                if let page = URL(string: "https://modrinth.com/resourcepack/\(p.slug)"), p.slug.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil {
                    Sep(inset: 16)
                    Link(destination: page) {
                        RowLabel(symbol: "safari.fill", title: "Open on Modrinth", detail: "modrinth.com/resourcepack/\(p.slug)")
                    }.buttonStyle(.plain)
                }
            }
            textCard("What the app checks", "The file must come from Modrinth's file server, match the size and SHA-512 Modrinth lists, be a ZIP whose paths are all plain, and have pack.mcmeta at its root. Modrinth packs are not reviewed by Horizon.")
        }
    }

    // MARK: pieces

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.subheadline).foregroundStyle(.secondary).frame(width: 92, alignment: .leading)
            Text(value).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private func textCard(_ title: String?, _ body: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.headline) }
            Text(body).font(big ? .body.weight(.medium) : .subheadline).foregroundStyle(big ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 24)
    }

    private func notice(_ text: String, warn: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: "exclamationmark.triangle.fill", tone: warn ? .warn : .brand2, size: 36)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22, tint: (warn ? Palette.warn : brand2).opacity(0.18))
    }

    private func gallery(_ urls: [String]) -> some View {
        let shots = urls.filter { HZMarketIndex.isRegistryImageURL($0) }.compactMap { URL(string: $0) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(shots, id: \.self) { url in
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Rectangle().fill(Color.primary.opacity(0.08)).overlay(ProgressView()) }
                    }
                    .frame(width: 260, height: 146)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }
}
