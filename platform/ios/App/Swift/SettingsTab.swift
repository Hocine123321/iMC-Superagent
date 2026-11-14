import SwiftUI
import UIKit

/// The scaffold every settings page shares: the backdrop, a scrolling column and a small title.
struct Page<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        ScrollView {
            GlassStack(spacing: 18) {
                VStack(spacing: 16) { content }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The third tab: a short list of places. Each opens a page of its own.
struct SettingsTab: View {
    enum Route: Hashable { case account, look, game, marketplace, download, files, fileManager, diagnostics, about, developer }
    @State private var path: [Route] = []
    @ObservedObject private var prefs = Prefs.shared
    @State private var accountName: String? = nil
    @State private var confirmReset = false
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                GlassStack(spacing: 18) {
                    VStack(spacing: 18) {
                        accountCard
                        GlassGroup {
                            link(.look, "paintpalette.fill", .brand, "Look", "Appearance, colours, haptics.")
                            Sep()
                            link(.game, "gamecontroller.fill", .brand2, "Game", "Start-up, Play, downloads.")
                            Sep()
                            link(.marketplace, "shippingbox.fill", .brand, "Marketplace", "What the Packs tab shows.")
                        }
                        GlassGroup {
                            link(.download, "arrow.down.circle.fill", .brand2, "Download Minecraft", "Get the game files from Mojang.")
                            Sep()
                            link(.files, "externaldrive.fill", .brand, "Game files", "Import, check or replace them.")
                            Sep()
                            link(.fileManager, "folder.fill", .brand2, "File manager", "Everything in the Horizon folder.")
                        }
                        GlassGroup {
                            link(.diagnostics, "stethoscope", .brand, "Diagnostics", "Run a check, read the logs.")
                            Sep()
                            link(.about, "info.circle.fill", .brand2, "About", "Version, licences, credits.")
                        }
                        if prefs.devMode {
                            GlassGroup {
                                link(.developer, "hammer.fill", .brand, "Developer options", "Experimental features, for testers.")
                            }
                        }
                        Button(role: .destructive) { confirmReset = true } label: {
                            Text("Reset launcher settings").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .secondaryAction().tint(brand2)
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
                }
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .account: AccountPage()
                case .look: LookSettingsPage()
                case .game: GameSettingsPage()
                case .marketplace: MarketplaceSettingsPage()
                case .download: DownloadPage()
                case .files: GameFilesPage()
                case .fileManager: FileManagerPage(path: "")
                case .diagnostics: DiagnosticsPage()
                case .about: AboutPage()
                case .developer: DeveloperPage()
                }
            }
            .alert("Reset launcher settings?", isPresented: $confirmReset) {
                Button("Reset", role: .destructive) { prefs.resetLauncherSettings() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Look, start-up and Marketplace choices go back to what they were on a new install. Your files, worlds, sign-in and the game's own settings are kept.")
            }
            .onAppear { accountName = HZAccountStore.shared().account()?.name }
        }
    }

    private var accountCard: some View {
        Button { Haptics.tap(); path.append(.account) } label: {
            HStack(spacing: 14) {
                Image(systemName: accountName == nil ? "person.crop.circle" : "person.crop.circle.fill")
                    .font(.system(size: 38)).foregroundStyle(brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text(accountName ?? "Not signed in").font(.title3.weight(.semibold))
                    Text(accountName == nil ? "Sign in to download the game." : "Microsoft account · tap to manage")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(18).frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 28, tint: brand.opacity(0.18), interactive: true)
    }

    private func link(_ route: Route, _ symbol: String, _ tone: IconTile.Tone, _ title: String, _ detail: String) -> some View {
        Button { Haptics.select(); path.append(route) } label: {
            RowLabel(symbol: symbol, tone: tone, title: title, detail: detail)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Look

struct SliderRow: View {
    let title: String
    var detail: String? = nil
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var leading: String? = nil
    var trailing: String? = nil
    var valueText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.body.weight(.semibold))
                Spacer()
                if let valueText { Text(valueText).font(.subheadline).foregroundStyle(.secondary) }
            }
            if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Slider(value: $value, in: range)
            if leading != nil || trailing != nil {
                HStack {
                    Text(leading ?? "").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(trailing ?? "").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

struct LookSettingsPage: View {
    @ObservedObject private var prefs = Prefs.shared
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2

    var body: some View {
        Page("Look") {
            preview
            SectionLabel("Appearance")
            GlassGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Theme").font(.body.weight(.semibold))
                    Picker("Theme", selection: $prefs.appearance) {
                        Text("System").tag(0)
                        Text("Dark").tag(1)
                        Text("Light").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            SectionLabel("Colours")
            presetGrid
            GlassGroup {
                colourRow("First colour", "The accent: buttons, switches, the tab bar.", first: true)
                Sep(inset: 16)
                colourRow("Second colour", "The glow in the opposite corner and the second icon colour.", first: false)
                Sep(inset: 16)
                HStack(spacing: 12) {
                    Button { Haptics.tap(); prefs.swapColours() } label: {
                        Label("Swap", systemImage: "arrow.left.arrow.right").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .secondaryAction()
                    Button { Haptics.tap(); prefs.apply(ThemePreset.standard) } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .secondaryAction().disabled(prefs.activePreset == ThemePreset.standard && prefs.balance == ThemePreset.standard.balance)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                Sep(inset: 16)
                SliderRow(title: "Colour balance", detail: "How the two colours mix behind the launcher.",
                          value: $prefs.balance, leading: "First colour", trailing: "Second colour")
                Sep(inset: 16)
                SliderRow(title: "Backdrop colour", detail: "How strongly the colour shows.",
                          value: $prefs.intensity, valueText: "\(Int((prefs.intensity * 100).rounded())) %")
            }
            SectionLabel("App icon")
            GlassGroup {
                ToggleRow(symbol: "app.badge.fill", title: "Match the colour theme",
                          detail: "The icon on the home screen follows the theme (a custom colour pair gets the nearest theme's icon). Pick an icon below to choose one by hand instead.",
                          isOn: $prefs.matchIcon)
            }
            iconGrid
            Text("iOS shows a short notice each time the icon changes; an app cannot turn that off.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 20)
            SectionLabel("Performance")
            GlassGroup {
                ToggleRow(symbol: "gauge.with.dots.needle.33percent", title: "Lightweight visuals",
                          detail: "Draws list rows, groups, chips and small pills as flat tinted shapes instead of Liquid Glass. The big cards and the system's own bars keep their glass. Easier on an older phone and on the battery.",
                          isOn: $prefs.lightweight)
                Sep()
                ToggleRow(symbol: "battery.25percent", tone: .brand2, title: "Also in Low Power Mode",
                          detail: "Switches to lightweight visuals by itself while Low Power Mode is on.",
                          isOn: $prefs.lightweightAuto)
            }
            SectionLabel("Feel")
            GlassGroup {
                ToggleRow(symbol: "hand.tap.fill", title: "Haptics", detail: "A light tap on buttons and tabs.", isOn: $prefs.haptics)
                Sep()
                ToggleRow(symbol: "wind", tone: .brand2, title: "Reduce motion", detail: "No bounce on switches and tabs.", isOn: $prefs.reduceMotion)
                Sep()
                ToggleRow(symbol: "list.bullet", title: "Compact lists", detail: "Marketplace rows without the description line.", isOn: $prefs.compactLists)
            }
        }
    }

    private var preview: some View {
        HStack(spacing: 16) {
            BrandMark().frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 8) {
                Text("iMC Horizon").font(.system(.title3, design: .rounded).weight(.bold))
                HStack(spacing: 8) {
                    Capsule().fill(brand).frame(width: 54, height: 12)
                    Capsule().fill(brand2).frame(width: 54, height: 12)
                }
            }
            Spacer()
        }
        .padding(18).frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 28, tint: brand.opacity(0.18))
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(ThemePreset.all) { preset in presetButton(preset) }
        }
    }

    /// The nine icons, as the home screen will show them. The one showing (or wanted) has a ring.
    private var iconGrid: some View {
        let wanted = prefs.matchIcon ? AppIconTheme.nearest(prefs.colour1, prefs.colour2).id : prefs.iconChoice
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
            ForEach(ThemePreset.all) { preset in
                let selected = preset.id == wanted
                Button { Haptics.select(); AppIconTheme.choose(preset) } label: {
                    VStack(spacing: 8) {
                        IconPreview(preset: preset, size: 72)
                            .overlay(RoundedRectangle(cornerRadius: 72 * 0.225, style: .continuous).strokeBorder(selected ? brand : Color.clear, lineWidth: 3).padding(-3))
                        Text(preset.name).font(.caption.weight(selected ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(preset.name) icon")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }

    private func presetButton(_ preset: ThemePreset) -> some View {
        let selected = prefs.activePreset == preset
        return Button { Haptics.select(); prefs.apply(preset) } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Palette.plain(hex: preset.first)).frame(width: 26, height: 26).offset(x: -8)
                    Circle().fill(Palette.plain(hex: preset.second)).frame(width: 26, height: 26).offset(x: 8)
                }
                .frame(width: 44, height: 28)
                Text(preset.name).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(brand) }
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 18, tint: selected ? brand.opacity(0.25) : nil, interactive: true, repeated: true)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func colourRow(_ title: String, _ detail: String, first: Bool) -> some View {
        let binding = Binding<Color>(
            get: { Palette.plain(hex: first ? prefs.colour1 : prefs.colour2) },
            set: { c in
                let hex = Palette.hex(from: c)
                if first { prefs.colour1 = hex } else { prefs.colour2 = hex }
            })
        return HStack(spacing: 14) {
            IconTile(symbol: "eyedropper.halffull", tone: first ? .brand : .brand2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ColorPicker(title, selection: binding, supportsOpacity: false).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: - Game

struct GameSettingsPage: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Page("Game") {
            SectionLabel("Start")
            GlassGroup {
                ToggleRow(symbol: "bolt.fill", title: "Open straight into the game",
                          detail: "Skips the launcher when the game files are ready. It comes back after a crash, or when a file named open-launcher is in the Horizon folder.",
                          isOn: $prefs.opensGameDirectly)
                Sep()
                ToggleRow(symbol: "questionmark.circle.fill", tone: .brand2, title: "Ask before Play",
                          detail: "Play closes the app and the game starts the next time it opens. This asks first.",
                          isOn: $prefs.confirmPlay)
            }
            SectionLabel("Downloads")
            GlassGroup {
                ToggleRow(symbol: "sun.max.fill", title: "Keep the screen on while downloading",
                          detail: "A download pauses when the phone locks. This stops it from locking until the download ends.",
                          isOn: $prefs.keepAwake)
            }
            SectionLabel("Account")
            GlassGroup {
                ToggleRow(symbol: "person.crop.square.fill", tone: .brand2, title: "Show my Minecraft head",
                          detail: "Loads your skin from Mojang's own servers to show it on the Account page. Off, nothing extra is requested.",
                          isOn: $prefs.showHead)
            }
        }
    }
}

// MARK: - Marketplace

struct MarketplaceSettingsPage: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Page("Marketplace") {
            SectionLabel("Sources")
            GlassGroup {
                ToggleRow(symbol: "globe", title: "Modrinth resource packs",
                          detail: "Adds a Modrinth tab with thousands of packs for 26.3. They come from Modrinth's servers and are not reviewed by Horizon.",
                          isOn: $prefs.useModrinth)
            }
            SectionLabel("What to show")
            GlassGroup {
                ToggleRow(symbol: "puzzlepiece.extension.fill", tone: .brand2, title: "Show mods",
                          detail: "Adds a Mods tab. Mods change the game and are off in the game until you turn them on.",
                          isOn: $prefs.showMods)
                Sep()
                ToggleRow(symbol: "sparkles", title: "Show shaders",
                          detail: "Adds a Shaders tab. Shaders have not been tested on a phone.",
                          isOn: $prefs.showShaders)
                Sep()
                ToggleRow(symbol: "square.grid.2x2.fill", tone: .brand2, title: "Show everything else",
                          detail: "Adds an Everything tab, including native mods and kinds the app cannot install yet.",
                          isOn: $prefs.showOtherKinds)
            }
            SectionLabel("Installing")
            GlassGroup {
                ToggleRow(symbol: "checkmark.shield.fill", title: "Ask before installing",
                          detail: "Shows what will happen and the download size first.",
                          isOn: $prefs.confirmInstalls)
            }
        }
    }
}
