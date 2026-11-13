import SwiftUI
import UIKit

// MARK: - Rows

struct MarketRow: Identifiable, Hashable {
    enum State { case get, installed, unavailable }
    enum Payload { case horizon(HZMarketProject), modrinth(HZModrinthProject) }

    let id: String
    let title: String
    let kind: String
    let source: String
    let summary: String
    var state: State
    var stateText: String
    var iconURL: URL?
    let payload: Payload

    static func == (a: MarketRow, b: MarketRow) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum MarketKind {
    static func symbol(_ kind: String) -> String {
        switch kind {
        case "resourcepack": return "paintpalette.fill"
        case "mod": return "puzzlepiece.extension.fill"
        case "native-mod": return "cpu.fill"
        case "shader", "shaderpack": return "sun.max.fill"
        case "modpack": return "shippingbox.fill"
        case "datapack": return "doc.zipper"
        default: return "cube.fill"
        }
    }
    static func tone(_ kind: String) -> IconTile.Tone {
        switch kind {
        case "resourcepack": return .brand
        case "mod", "modpack": return .brand2
        case "shader", "shaderpack": return .warn
        case "datapack": return .ok
        default: return .neutral
        }
    }
    static func name(_ kind: String) -> String {
        switch kind {
        case "mod": return "Mod"
        case "native-mod": return "Native mod"
        case "resourcepack": return "Resource pack"
        case "shader": return "Shader"
        case "modpack": return "Modpack"
        case "shaderpack": return "Shader pack"
        case "datapack": return "Data pack"
        default: return kind
        }
    }
}

// MARK: - The list's controller

@MainActor
final class MarketController: ObservableObject {
    enum Tab: Int, CaseIterable, Identifiable {
        case packs, modrinth, mods, shaders, all, installed
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .packs: return "Resource packs"
            case .modrinth: return "Modrinth"
            case .mods: return "Mods"
            case .shaders: return "Shaders"
            case .all: return "Everything"
            case .installed: return "Installed"
            }
        }
    }

    @Published var tab: Tab = .packs
    @Published var query = ""
    @Published private(set) var rows: [MarketRow] = []
    @Published private(set) var tabs: [Tab] = [.packs, .installed]
    @Published private(set) var banner: String? = nil
    @Published private(set) var loading = false
    @Published private(set) var loadingModrinth = false
    @Published private(set) var modrinthError: String? = nil
    @Published private(set) var modrinthTotal = 0
    /// The page being shown, from 0. Modrinth's pages are 30 results fetched from its server; the other tabs are cut here.
    @Published private(set) var page = 0
    @Published private(set) var localCount = 0
    static let localPageSize = 25
    static let modrinthPageSize = 30
    private(set) var index: HZMarketIndex? = nil

    let game = "26.3"
    private var modrinthHits: [HZModrinthProject] = []
    private var modrinthQuery: String? = nil
    private var modrinthPageLoaded = 0
    private var modrinthPending = false
    private var searchTask: Task<Void, Never>? = nil
    private let client: HZMarketClient
    private let modrinth = HZModrinthClient()

    private var model: HZLauncherModel { HZLauncherModel.shared()! }
    private func installer() -> HZMarketInstaller { HZMarketInstaller(home: model.home) }

    init() {
        let dir = (HZLauncherModel.shared()!.root as NSString).appendingPathComponent("marketplace")
        client = HZMarketClient(cacheDirectory: dir)
        rebuildTabs()
        load(force: false)
    }

    // MARK: tabs

    func rebuildTabs() {
        let p = Prefs.shared
        var t: [Tab] = [.packs]
        if p.useModrinth { t.append(.modrinth) }
        if p.showMods { t.append(.mods) }
        if p.showShaders { t.append(.shaders) }
        if p.showOtherKinds { t.append(.all) }
        t.append(.installed)
        tabs = t
        if !t.contains(tab) { tab = .packs }
        refilter()
    }

    func select(_ t: Tab) {
        guard t != tab else { return }
        tab = t
        page = 0
        if t == .modrinth && modrinthHits.isEmpty { searchModrinth(force: false) }
        refilter()
    }

    // MARK: pages

    var pageCount: Int {
        if tab == .modrinth { return max(1, Int((Double(modrinthTotal) / Double(Self.modrinthPageSize)).rounded(.up))) }
        return max(1, Int((Double(localCount) / Double(Self.localPageSize)).rounded(.up)))
    }

    func goTo(_ p: Int) {
        let target = min(max(0, p), pageCount - 1)
        guard target != page else { return }
        page = target
        if tab == .modrinth { searchModrinth(force: true) } else { refilter() }
    }

    // MARK: loading

    func load(force: Bool) {
        guard !loading else { return }
        loading = true
        refilter()
        client.load(force: force) { [weak self] r in
            Task { @MainActor in
                guard let self else { return }
                self.loading = false
                if let idx = r.index {
                    self.index = idx
                    if r.source.rawValue == 2 {   // HZMarketOffline
                        let when = r.fetched.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? ""
                        self.banner = "Offline. Showing the copy from \(when)."
                    } else { self.banner = nil }
                } else {
                    self.index = nil
                    self.banner = r.error ?? "The Marketplace could not be loaded."
                }
                self.refilter()
            }
        }
    }

    func reload() {
        load(force: true)
        if tab == .modrinth { searchModrinth(force: true) }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Searches Modrinth for what is typed. If a search is already running, the newer text is searched as soon as it
    /// returns (an answer for older text is never shown), so typing quickly cannot leave stale results.
    func searchModrinth(force: Bool) {
        guard Prefs.shared.useModrinth else { return }
        let q = trimmedQuery, wantedPage = page
        if loadingModrinth { modrinthPending = true; return }
        if !force && q == (modrinthQuery ?? "") && wantedPage == modrinthPageLoaded && !modrinthHits.isEmpty { return }
        loadingModrinth = true; modrinthError = nil; modrinthQuery = q; modrinthPageLoaded = wantedPage; modrinthPending = false
        refilter()
        modrinth.searchText(q, offset: UInt(wantedPage * Self.modrinthPageSize)) { [weak self] projects, total, error in
            Task { @MainActor in
                guard let self else { return }
                self.loadingModrinth = false
                let stale = q != self.trimmedQuery || wantedPage != self.page
                if !stale {
                    self.modrinthHits = projects ?? []
                    self.modrinthTotal = Int(total)
                    self.modrinthError = error
                }
                if stale || self.modrinthPending { self.modrinthPending = false; self.searchModrinth(force: false); return }
                self.refilter()
            }
        }
    }

    /// Modrinth is searched on its server, a moment after typing stops.
    func queryChanged() {
        page = 0
        if tab == .modrinth {
            searchTask?.cancel()
            searchTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                self?.searchModrinth(force: false)
            }
        }
        refilter()
    }

    // MARK: rows

    private func iconURL(registry: String?) -> URL? {
        guard let s = registry, !s.isEmpty, HZMarketIndex.isRegistryImageURL(s) else { return nil }
        return URL(string: s)
    }

    private func iconURL(modrinth s: String?) -> URL? {
        guard let s, let u = URL(string: s), u.scheme == "https", u.host == "cdn.modrinth.com" else { return nil }
        return u
    }

    private func row(_ p: HZMarketProject, _ inst: HZMarketInstaller) -> MarketRow {
        let have = inst.installedEntry(project: p.projectId)
        let v = index?.installableVersion(of: p, game: game)
        let refusal: String? = (v != nil && index != nil) ? HZMarketInstaller.refusal(for: p, version: v!, index: index!) : "No version for \(game)"
        var state = MarketRow.State.unavailable
        var text = ""
        if let have {
            state = .installed
            text = have.version.isEmpty ? "Installed" : "v" + have.version
        } else if refusal == nil {
            state = .get; text = "Get"
        } else {
            text = p.support.rawValue == 1 ? "Desktop only" : ((p.key ?? "").isEmpty ? "Unavailable" : "Signed")
        }
        return MarketRow(id: "h:" + p.projectId, title: p.name, kind: p.kind, source: "Horizon", summary: p.summary,
                         state: state, stateText: text, iconURL: iconURL(registry: p.icon), payload: .horizon(p))
    }

    private func row(_ p: HZModrinthProject, _ inst: HZMarketInstaller) -> MarketRow {
        let have = inst.installedEntry(modrinth: p.projectId)
        var state = MarketRow.State.get
        var text = "Get"
        if let have { state = .installed; text = have.version.isEmpty ? "Installed" : "v" + have.version }
        return MarketRow(id: "m:" + p.projectId, title: p.title, kind: "resourcepack", source: "Modrinth", summary: p.summary,
                         state: state, stateText: text, iconURL: iconURL(modrinth: p.iconURL), payload: .modrinth(p))
    }

    func refilter() {
        let inst = installer()
        let q = trimmedQuery.lowercased()
        var out: [MarketRow] = []
        if tab == .modrinth {
            out = modrinthHits.map { row($0, inst) }
        } else {
            var list: [HZMarketProject] = []
            for p in index?.projects ?? [] {
                switch tab {
                case .installed: if inst.installedEntry(project: p.projectId) == nil { continue }
                case .packs: if p.kind != "resourcepack" { continue }
                case .mods: if p.kind != "mod" && p.kind != "native-mod" { continue }
                case .shaders: if p.kind != "shader" && p.kind != "shaderpack" { continue }
                case .all: if !HZPrefs.isKindVisible(p.kind) { continue }
                case .modrinth: continue
                }
                if !q.isEmpty {
                    let hay = ([p.name, p.summary, p.projectId, p.categories.joined(separator: " "), p.authors.joined(separator: " ")]
                        .joined(separator: " ")).lowercased()
                    if !q.split(separator: " ").allSatisfy({ hay.contains($0) }) { continue }
                }
                list.append(p)
            }
            list.sort { a, b in
                if a.downloads != b.downloads { return a.downloads > b.downloads }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            out = list.map { row($0, inst) }
            // The Installed tab also lists Modrinth packs the app put on the phone.
            if tab == .installed {
                for e in inst.installed() where e.source == "modrinth" {
                    if !q.isEmpty && !e.title.lowercased().contains(q) { continue }
                    let mp = HZModrinthProject()
                    mp.projectId = e.projectId; mp.title = e.title; mp.slug = e.projectId
                    mp.summary = ""; mp.author = ""; mp.license = ""
                    out.append(MarketRow(id: "m:" + e.projectId, title: e.title, kind: "resourcepack", source: "Modrinth", summary: "",
                                         state: .installed, stateText: e.version.isEmpty ? "Installed" : "v" + e.version, iconURL: nil, payload: .modrinth(mp)))
                }
            }
        }
        if tab != .modrinth {
            // The other tabs are cut into pages here.
            localCount = out.count
            let pages = max(1, Int((Double(out.count) / Double(Self.localPageSize)).rounded(.up)))
            if page >= pages { page = pages - 1 }
            let start = page * Self.localPageSize
            out = Array(out[min(start, out.count)..<min(start + Self.localPageSize, out.count)])
        }
        rows = out
    }

    var footer: String? {
        let busy = tab == .modrinth ? loadingModrinth : loading
        if busy { return "Loading..." }
        if tab == .modrinth, let e = modrinthError { return e }
        if rows.isEmpty {
            if tab == .installed { return "Nothing installed yet." }
            if index == nil && tab != .modrinth { return banner ?? "The Marketplace could not be loaded." }
            return "Nothing matches."
        }
        if tab == .modrinth {
            let from = page * Self.modrinthPageSize + 1
            return "Showing \(from) to \(from + rows.count - 1) of \(modrinthTotal) resource packs for Minecraft \(game) on Modrinth."
        }
        if localCount > Self.localPageSize {
            let from = page * Self.localPageSize + 1
            return "Showing \(from) to \(from + rows.count - 1) of \(localCount)." + (banner.map { " " + $0 } ?? "")
        }
        return banner
    }
}

// MARK: - The tab

struct MarketplaceTab: View {
    @StateObject private var c = MarketController()
    @ObservedObject private var prefs = Prefs.shared
    @Environment(\.brand) private var brand

    private var signature: String { "\(prefs.useModrinth)\(prefs.showMods)\(prefs.showShaders)\(prefs.showOtherKinds)" }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
              ScrollView {
                GlassStack(spacing: 14) {
                    LazyVStack(spacing: 12) {
                        chips.id("top")
                        if c.pageCount > 1 { PagerBar(page: c.page, pages: c.pageCount, goTo: { c.goTo($0) }) }
                        ForEach(c.rows) { row in
                            NavigationLink(value: row) { MarketRowView(row: row, compact: prefs.compactLists) }
                                .buttonStyle(.plain)
                        }
                        if let footer = c.footer {
                            Text(footer).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                .padding(.horizontal, 24).padding(.top, 10)
                        }
                        if c.pageCount > 1 && !c.rows.isEmpty { PagerBar(page: c.page, pages: c.pageCount, goTo: { c.goTo($0) }) }
                    }
                    .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 40)
                }
              }
              // A new page starts at the top.
              .onChange(of: c.page) { _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { c.reload() }
            .screenBackground()
            .navigationTitle("Marketplace")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $c.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Haptics.tap(); c.reload() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Refresh")
                }
            }
            .navigationDestination(for: MarketRow.self) { MarketDetailPage(row: $0, index: c.index) }
        }
        .onChange(of: c.query) { _ in c.queryChanged() }
        .onChange(of: signature) { _ in c.rebuildTabs() }
        .onAppear { c.refilter() }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(c.tabs) { t in
                    let on = c.tab == t
                    Button { Haptics.select(); c.select(t) } label: {
                        Text(t.title).font(.subheadline.weight(on ? .bold : .medium))
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .glassCapsule(tint: on ? brand.opacity(0.55) : nil, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 6)
        }
        // A fixed height and a margin below: the row is its own band, and the first card starts under it
        // instead of sliding beneath the chips (owner's screenshot, 2026-11-12). The side padding is inside the
        // scroll view so the chips can scroll to the screen edge while the first one lines up with the cards.
        .frame(height: 50)
        .padding(.horizontal, -20)
        .padding(.bottom, 6)
    }
}

/// First, previous, "Page 2 of 14", next, last. The page number is a menu, to jump straight to a page.
struct PagerBar: View {
    let page: Int
    let pages: Int
    let goTo: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            button("backward.end.fill", "First page", enabled: page > 0) { goTo(0) }
            button("chevron.left", "Previous page", enabled: page > 0) { goTo(page - 1) }
            Menu {
                ForEach(jumpTargets, id: \.self) { p in Button("Page \(p + 1)") { goTo(p) } }
            } label: {
                Text("Page \(page + 1) of \(pages)").font(.subheadline.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 14).padding(.vertical, 9).glassCapsule(interactive: true)
            }
            button("chevron.right", "Next page", enabled: page < pages - 1) { goTo(page + 1) }
            button("forward.end.fill", "Last page", enabled: page < pages - 1) { goTo(pages - 1) }
        }
        .frame(maxWidth: .infinity)
    }

    /// Every page when there are few; otherwise a spread of them, the neighbours of this one included.
    private var jumpTargets: [Int] {
        if pages <= 24 { return Array(0..<pages) }
        var set = Set<Int>([0, pages - 1, page])
        for i in 1..<12 { set.insert(i * pages / 12) }
        for d in -2...2 where page + d >= 0 && page + d < pages { set.insert(page + d) }
        return set.sorted()
    }

    private func button(_ symbol: String, _ label: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.select(); action() } label: {
            Image(systemName: symbol).font(.subheadline.weight(.bold)).frame(width: 38, height: 38)
                .glassCircle(interactive: true, repeated: true)
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}

/// A project's picture: its icon from the registry or Modrinth when it has one, otherwise a tile for its kind.
struct ProjectIcon: View {
    let kind: String
    let url: URL?
    var size: CGFloat = 52

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    IconTile(symbol: MarketKind.symbol(kind), tone: MarketKind.tone(kind), size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        } else {
            IconTile(symbol: MarketKind.symbol(kind), tone: MarketKind.tone(kind), size: size)
        }
    }
}

struct MarketRowView: View {
    let row: MarketRow
    let compact: Bool
    @Environment(\.brand) private var brand

    var body: some View {
        HStack(spacing: 14) {
            ProjectIcon(kind: row.kind, url: row.iconURL, size: compact ? 44 : 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Text("\(MarketKind.name(row.kind))  ·  \(row.source)").font(.caption).foregroundStyle(.secondary)
                if !compact && !row.summary.isEmpty {
                    Text(row.summary).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            pill
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .glassCard(cornerRadius: 22, interactive: true, repeated: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(MarketKind.name(row.kind)), \(row.stateText)")
    }

    @ViewBuilder private var pill: some View {
        switch row.state {
        case .get:
            Text(row.stateText).font(.footnote.weight(.bold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(brand))
        case .installed:
            Text(row.stateText).font(.footnote.weight(.semibold)).foregroundStyle(brand)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(brand.opacity(0.18)))
        case .unavailable:
            Text(row.stateText).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
    }
}
