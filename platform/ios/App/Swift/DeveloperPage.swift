import SwiftUI
import UIKit

/// Developer options: the features that are off by default because they are unfinished, untested, or only
/// useful to the people building the app. Unlocked by tapping the app mark in About three times (like the
/// Android build-number tap). Nothing here is needed to use the launcher; it only shows more of it.
///
/// The unlock is a launcher.txt line (`devMode:true`), so it survives restarts. "Turn off developer mode"
/// removes the Settings row again. Turning it off does not switch the features back off: each one keeps the
/// value it has here.
struct DeveloperPage: View {
    @ObservedObject private var prefs = Prefs.shared
    @Environment(\.brand) private var brand
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var version: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?" }
    private var build: String { (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?" }

    var body: some View {
        Page("Developer options") {
            warning

            SectionLabel("Experimental features")
            GlassGroup {
                ToggleRow(symbol: "play.rectangle.fill", title: "Play without closing the app",
                          detail: "Untested. Starts the game inside this run of the app, so Play no longer closes it. Close the app fully and open it again for this to apply. Blank screen at start? Delete the line inProcessPlay from launcher.txt in the Horizon folder.",
                          isOn: $prefs.inProcessPlay)
            }

            SectionLabel("Sign-in")
            GlassGroup {
                stateRow("person.badge.key.fill", .brand2, "Sign-in mode", signInMode.value, signInMode.kind)
                Sep()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Test mode (private)").font(.body.weight(.semibold))
                    Text("Signs in with another launcher's app ID while this project has none of its own. Not for sharing, and it can stop working at any time. To turn it on, put the ID on one line in test-client-id.txt in the Horizon folder (Files app, On My iPhone, iMC Horizon), then restart the app. Delete the file to turn it off. The app never saves the ID itself.")
                        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button {
                        Haptics.tap()
                        UIPasteboard.general.string = "test-client-id.txt"
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy the file name", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .secondaryAction().tint(brand)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }

            SectionLabel("This build")
            GlassGroup {
                stateRow("shippingbox.fill", .brand, "Launcher", "\(version) (\(build))", .info)
                Sep()
                stateRow("play.rectangle", .brand2, "Play without closing", prefs.inProcessPlay ? "On (next start)" : "Off", prefs.inProcessPlay ? .warn : .info)
                Sep()
                stateRow("bolt.fill", .brand, "Open straight into the game", prefs.opensGameDirectly ? "On" : "Off", .info)
                Sep()
                stateRow("lock.open.fill", .brand2, "Developer mode", "On", .ok)
            }

            Button(role: .destructive) {
                Haptics.warning()
                prefs.devMode = false
                dismiss()
            } label: {
                Text("Turn off developer mode").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
            }
            .secondaryAction().tint(brand)
            .padding(.top, 6)
        }
    }

    private var warning: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: "exclamationmark.triangle.fill", tone: .warn)
            VStack(alignment: .leading, spacing: 4) {
                Text("For developers and testers").font(.headline)
                Text("These features are unfinished or untested. They can crash the app or leave it on a blank screen.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 24)
    }

    private var signInMode: (value: String, kind: StatusPill.Kind) {
        if HZMicrosoftClientID() != nil { return ("This build's own app ID", .ok) }
        if HZSignInIsTestMode() { return ("Test mode", .warn) }
        return ("Not set up", .bad)
    }

    private func stateRow(_ symbol: String, _ tone: IconTile.Tone, _ title: String, _ value: String, _ kind: StatusPill.Kind) -> some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, tone: tone)
            Text(title).font(.body.weight(.semibold))
            Spacer(minLength: 8)
            StatusPill(kind: kind, text: value)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}
