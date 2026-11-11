import SwiftUI

/// Version, what this is, and the licences. The notices are the upstream files, bundled unchanged
/// (project.yml: horizon/LICENSE and horizon/THIRD_PARTY_NOTICES.md), so there is no copy to drift.
struct AboutPage: View {
    @Environment(\.brand) private var brand

    private var version: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?" }
    private var build: String { (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?" }

    var body: some View {
        Page("About") {
            VStack(spacing: 14) {
                BrandMark().frame(width: 96, height: 96)
                Text("iMC Horizon").font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("Launcher \(version) (\(build))  ·  Minecraft 26.3")
                    .font(.subheadline).foregroundStyle(.secondary)
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
