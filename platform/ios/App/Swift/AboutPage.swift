import SwiftUI

/// Version, what this is, and the licences. The notices are the upstream files, bundled unchanged
/// (project.yml: horizon/LICENSE and horizon/THIRD_PARTY_NOTICES.md), so there is no copy to drift.
struct AboutPage: View {
    @Environment(\.brand) private var brand
    @ObservedObject private var prefs = Prefs.shared
    // Developer options: three quick taps on the mark (see DeveloperPage.swift).
    @State private var taps = 0
    @State private var lastTap = Date.distantPast
    @State private var hint: String? = nil
    @State private var hintWork: DispatchWorkItem? = nil
    @State private var openDeveloper = false

    private var version: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?" }
    private var build: String { (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?" }
    /// The release this IPA was published as (vN), and its commit; stamped by CI, "dev"/"local" otherwise.
    private var tag: String { (Bundle.main.infoDictionary?["HZBuildTag"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "dev" }
    private var commit: String { (Bundle.main.infoDictionary?["HZCommit"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "local" }

    var body: some View {
        Page("About") {
            VStack(spacing: 14) {
                BrandMark().frame(width: 96, height: 96)
                    .contentShape(Rectangle())
                    .onTapGesture { tapMark() }
                Text("iMC Horizon").font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("Build \(tag)").font(.headline).foregroundStyle(brand)
                Text("Launcher \(version) (\(build))  ·  Minecraft 26.3")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Commit \(commit)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let hint {
                    Text(hint).font(.footnote.weight(.semibold)).foregroundStyle(brand)
                        .transition(.opacity)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .padding(.vertical, 18).frame(maxWidth: .infinity)

            card("What this is", "An unofficial iOS port of Horizon, a Minecraft: Java Edition client written in Rust. It is a personal engineering project, not a product of Mojang or Microsoft.")
            card("Not an official Minecraft product", "This app is not made by, approved by or associated with Mojang Studios, Microsoft or Xbox. Minecraft is a trademark of Mojang Studios. The app contains no Minecraft code or assets: you need your own copy of Minecraft: Java Edition, which this app downloads from Mojang's servers to your phone after you sign in with the account that owns it.")
            card("Built on", "Horizon, by Ludovic Marie and the Horizon contributors, under the MIT licence.")
            GlassGroup {
                linkRow("Horizon project site", "https://playhorizon.dev", "globe")
                Sep()
                linkRow("Horizon source", "https://github.com/horizon-rust/horizon", "chevron.left.forwardslash.chevron.right")
                Sep()
                linkRow("This app's source", "https://github.com/Hocine123321/iMC-Superagent", "shippingbox")
            }
            card("Privacy", "The launcher keeps its logs on the phone and sends them nowhere unless you share them yourself. The game itself sends Horizon's anonymous \"I'm playing\" ping to telemetry.playhorizon.dev once a minute while you play, as Horizon does on every platform.")
            GlassGroup {
                NavigationLink { TextPage(title: "Licence of Horizon", resource: "LICENSE") } label: {
                    RowLabel(symbol: "doc.text.fill", title: "Licence of Horizon", detail: "MIT, as shipped with Horizon.")
                }.buttonStyle(.plain)
                Sep()
                NavigationLink { TextPage(title: "Third-party notices", resource: "THIRD_PARTY_NOTICES.md") } label: {
                    RowLabel(symbol: "doc.on.doc.fill", tone: .brand2, title: "Third-party notices", detail: "From Horizon's THIRD_PARTY_NOTICES.md, unchanged.")
                }.buttonStyle(.plain)
            }
        }
        .navigationDestination(isPresented: $openDeveloper) { DeveloperPage() }
    }

    /// Three taps within two seconds of each other. From the second tap on, a line counts down (as Android does);
    /// the third opens Developer options and keeps developer mode on. Already on: it just opens the page.
    private func tapMark() {
        let now = Date()
        taps = now.timeIntervalSince(lastTap) > 2 ? 1 : taps + 1
        lastTap = now
        if taps >= 3 {
            taps = 0
            Haptics.success()
            if !prefs.devMode { prefs.devMode = true }
            show(nil)
            openDeveloper = true
            return
        }
        if prefs.devMode {
            show(taps == 2 ? "You are already a developer. One more tap opens the options." : nil)
        } else if taps == 2 {
            Haptics.select()
            show("One more tap to open developer options.")
        }
    }

    private func show(_ text: String?) {
        hintWork?.cancel()
        withAnimation { hint = text }
        guard text != nil else { hintWork = nil; return }
        let work = DispatchWorkItem { withAnimation { hint = nil } }
        hintWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func card(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 24)
    }

    private func linkRow(_ title: String, _ url: String, _ symbol: String) -> some View {
        Link(destination: URL(string: url)!) {
            RowLabel(symbol: symbol, title: title, detail: url.replacingOccurrences(of: "https://", with: ""))
        }
        .buttonStyle(.plain)
    }
}

/// A bundled text file shown whole, in a monospaced face.
struct TextPage: View {
    let title: String
    let resource: String

    private var text: String {
        let name = (resource as NSString).deletingPathExtension
        let ext = (resource as NSString).pathExtension
        guard let path = Bundle.main.path(forResource: name, ofType: ext.isEmpty ? nil : ext),
              let s = try? String(contentsOfFile: path, encoding: .utf8) else {
            return "This file is missing from this build. It is in the source repository as horizon/\(resource)."
        }
        return s
    }

    var body: some View {
        ScrollView {
            LongText(text: text)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 22)
                .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .screenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
