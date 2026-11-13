import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FolderRoute: Hashable { let path: String }
struct FileRoute: Hashable { let path: String; let name: String }

/// A share sheet (AirDrop, Messages, Save to Files) for one file.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ShareItem: Identifiable { let id = UUID(); let url: URL }

/// One folder of the Horizon folder. Nothing outside the Horizon folder can be reached: HZFileBrowser refuses paths
/// that leave it, and warns before deleting anything that cannot be remade (worlds, the sign-in).
@MainActor
final class FolderController: ObservableObject {
    let path: String
    let browser: HZFileBrowser
    @Published var entries: [HZFileEntry] = []
    @Published var error: String? = nil
    @Published var sizes: [String: UInt64] = [:]
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var showAlert = false
    @Published var free: Int64 = 0

    init(path: String) {
        self.path = path
        browser = HZFileBrowser(root: LauncherFile.root)
    }

    func reload() {
        var err: NSString?
        let list = browser.listFolder(path, error: &err)
        entries = list ?? []
        error = list == nil ? (err as String?) : nil
        free = LauncherState.freeSpace(at: LauncherFile.root)
        // Folder sizes walk the disk: measured off the main thread, one at a time, and filled in as they come.
        let folders = entries.filter { $0.isFolder }
        let b = browser
        DispatchQueue.global(qos: .utility).async {
            for f in folders {
                let s = b.size(of: f.relativePath)
                DispatchQueue.main.async { self.sizes[f.relativePath] = s }
            }
        }
    }

    func say(_ title: String, _ message: String) { alertTitle = title; alertMessage = message; showAlert = true }

    func risk(of e: HZFileEntry) -> Int { Int(browser.deleteRisk(of: e.relativePath).rawValue) }   // 0 ordinary, 1 world, 2 game files, 3 account, 4 forbidden

    func warning(for e: HZFileEntry) -> String {
        HZFileBrowser.warning(for: browser.deleteRisk(of: e.relativePath), name: e.name, size: e.isFolder ? (sizes[e.relativePath] ?? 0) : e.size)
    }

    func delete(_ e: HZFileEntry) {
        if let bad = browser.deletePath(e.relativePath) { say("Could not delete", bad) }
        reload()
    }

    func rename(_ e: HZFileEntry, to name: String) {
        if let bad = browser.renamePath(e.relativePath, to: name) { say("Could not rename", bad) }
        reload()
    }

    func newFolder(_ name: String) {
        if let bad = browser.createFolderNamed(name, inside: path) { say("Could not create the folder", bad) }
        reload()
    }

    func absolute(_ e: HZFileEntry) -> URL? {
        browser.resolve(e.relativePath).map { URL(fileURLWithPath: $0) }
    }

    func add(_ urls: [URL]) {
        let browser = self.browser, folder = path
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var problems: [String] = []
            var added = 0
            for src in urls {
                let scoped = src.startAccessingSecurityScopedResource()
                defer { if scoped { src.stopAccessingSecurityScopedResource() } }
                let name = src.lastPathComponent
                let bad = HZFileBrowser.problem(withName: name)
                let dest = bad == nil ? browser.resolve(HZFileBrowser.join(folder, name: name)) : nil
                let need = ((try? fm.attributesOfItem(atPath: src.path))?[.size] as? NSNumber)?.uint64Value ?? 0
                let free = ((try? fm.attributesOfFileSystem(forPath: browser.root))?[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
                if bad != nil || dest == nil { problems.append("\(name): \(bad ?? "not allowed here")") }
                else if fm.fileExists(atPath: dest!) { problems.append("\(name): something with that name is already here") }
                else if free > 0 && free < need + (100 << 20) { problems.append("\(name): not enough space") }
                else {
                    do { try fm.copyItem(atPath: src.path, toPath: dest!); added += 1 }
                    catch { problems.append("\(name): \(error.localizedDescription)") }
                }
            }
            DispatchQueue.main.async {
                self.reload()
                if !problems.isEmpty { self.say(added > 0 ? "Some files were not added" : "Nothing was added", problems.joined(separator: "\n")) }
            }
        }
    }
}

struct FileManagerPage: View {
    let path: String
    @StateObject private var c: FolderController
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2
    @State private var renaming: HZFileEntry? = nil
    @State private var renameText = ""
    @State private var creating = false
    @State private var newName = ""
    @State private var deleting: HZFileEntry? = nil
    @State private var sharing: ShareItem? = nil
    @State private var picking = false

    init(path: String) {
        self.path = path
        _c = StateObject(wrappedValue: FolderController(path: path))
    }

    private var core: some View {
        List {
            if let error = c.error {
                Text(error).foregroundStyle(.secondary).listRowBackground(Color.clear)
            }
            ForEach(c.entries, id: \.relativePath) { e in row(e) }
            Text(footer).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(path.isEmpty ? "Files" : (path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { newName = ""; creating = true } label: { Label("New folder", systemImage: "folder.badge.plus") }
                    Button { picking = true } label: { Label("Add files from the Files app", systemImage: "square.and.arrow.down") }
                } label: { Image(systemName: "plus") }
            }
        }
        .onAppear { c.reload() }
        .refreshable { c.reload() }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { c.add(urls) }
        }
        .sheet(item: $sharing) { ShareSheet(items: [$0.url]).ignoresSafeArea() }
        .alert(c.alertTitle, isPresented: $c.showAlert) { Button("OK", role: .cancel) {} } message: { Text(c.alertMessage) }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText).autocorrectionDisabled().textInputAutocapitalization(.never)
            Button("Rename") { if let e = renaming { c.rename(e, to: renameText) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("New folder", isPresented: $creating) {
            TextField("Name", text: $newName).autocorrectionDisabled().textInputAutocapitalization(.never)
            Button("Create") { c.newFolder(newName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert(deleting.map { "Delete \($0.name)?" } ?? "Delete?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button((deleting.map { c.risk(of: $0) } ?? 0) == 0 ? "Delete" : "Delete anyway", role: .destructive) {
                if let e = deleting { c.delete(e) }; deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text(deleting.map { c.warning(for: $0) } ?? "") }
    }

    /// The folder at the root of the stack knows how to open a folder or a text file; the pages it pushes do not repeat that.
    var body: some View {
        if path.isEmpty {
            core
                .navigationDestination(for: FolderRoute.self) { FileManagerPage(path: $0.path) }
                .navigationDestination(for: FileRoute.self) { TextFilePage(route: $0, browser: c.browser) }
        } else {
            core
        }
    }

    private var footer: String {
        "\(c.entries.count) items. \(ByteText.string(c.free)) free on this phone. Everything here is inside the Horizon folder; nothing outside it can be reached."
    }

    @ViewBuilder private func row(_ e: HZFileEntry) -> some View {
        let content = HStack(spacing: 14) {
            IconTile(symbol: symbol(for: e), tone: e.isFolder ? .brand : .neutral, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(.body.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Text(detail(e)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if e.isFolder { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .tintedCard(cornerRadius: 20)

        Group {
            if e.isFolder {
                NavigationLink(value: FolderRoute(path: e.relativePath)) { content }.buttonStyle(.plain)
            } else if isText(e) {
                NavigationLink(value: FileRoute(path: e.relativePath, name: e.name)) { content }.buttonStyle(.plain)
            } else {
                Button { if let u = c.absolute(e) { sharing = ShareItem(url: u) } } label: { content }.buttonStyle(.plain)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { askDelete(e) } label: { Label("Delete", systemImage: "trash") }
            Button { renameText = e.name; renaming = e } label: { Label("Rename", systemImage: "pencil") }.tint(.gray)
            if !e.isFolder {
                Button { if let u = c.absolute(e) { sharing = ShareItem(url: u) } } label: { Label("Share", systemImage: "square.and.arrow.up") }.tint(brand)
            }
        }
        .contextMenu {
            Button { renameText = e.name; renaming = e } label: { Label("Rename", systemImage: "pencil") }
            if !e.isFolder { Button { if let u = c.absolute(e) { sharing = ShareItem(url: u) } } label: { Label("Share", systemImage: "square.and.arrow.up") } }
            Button(role: .destructive) { askDelete(e) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func askDelete(_ e: HZFileEntry) {
        let r = c.risk(of: e)
        if r >= 3 { c.say("Not here", c.warning(for: e)); return }   // the Horizon folder itself, or the sign-in record
        deleting = e
    }

    private func detail(_ e: HZFileEntry) -> String {
        let size = e.isFolder ? (c.sizes[e.relativePath].map { ByteText.string(Int64(clamping: $0)) } ?? "...") : ByteText.string(Int64(clamping: e.size))
        let date = e.modified.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) } ?? ""
        return "\(size)   \(date)"
    }

    private func symbol(for e: HZFileEntry) -> String {
        if e.isFolder { return "folder.fill" }
        switch (e.name as NSString).pathExtension.lowercased() {
        case "txt", "log", "md": return "doc.text.fill"
        case "json", "toml", "cfg", "properties", "mcmeta", "xml", "yml", "yaml", "snbt", "lang": return "curlybraces"
        case "png", "jpg", "jpeg", "webp": return "photo.fill"
        case "zip", "jar", "hmod": return "doc.zipper"
        case "ogg", "wav", "mp3": return "waveform"
        default: return "doc.fill"
        }
    }

    /// Text files up to 256 KB open in the app; everything else goes to the share sheet.
    private func isText(_ e: HZFileEntry) -> Bool {
        let ext = (e.name as NSString).pathExtension.lowercased()
        let texty = ["txt", "log", "json", "csv", "md", "toml", "cfg", "properties", "mcmeta", "xml", "yml", "yaml", "snbt", "lang"].contains(ext) || e.name == "options.txt"
        return texty && e.size <= 256 * 1024
    }
}

struct TextFilePage: View {
    let route: FileRoute
    let browser: HZFileBrowser
    @State private var text: String? = nil
    @State private var sharing: ShareItem? = nil

    var body: some View {
        ScrollView {
            Group {
                if let text { LongText(text: text) } else { Text("This file is not UTF-8 text.").foregroundStyle(.secondary) }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .tintedCard(cornerRadius: 22)
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .screenBackground()
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { if let p = browser.resolve(route.path) { sharing = ShareItem(url: URL(fileURLWithPath: p)) } } label: { Image(systemName: "square.and.arrow.up") }
            }
        }
        .sheet(item: $sharing) { ShareSheet(items: [$0.url]).ignoresSafeArea() }
        .onAppear {
            if let p = browser.resolve(route.path), let d = try? Data(contentsOf: URL(fileURLWithPath: p)) {
                text = String(data: d, encoding: .utf8)
            }
        }
    }
}
