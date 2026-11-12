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
    @State private var idText = ""
    @State private var idProblem: String? = nil
    @State private var idSaved = false
    @State private var storedID: String? = HZLegacyTestClientID()
    @FocusState private var idFocused: Bool

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
                testModeEditor
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

    /// Paste another launcher's app ID here instead of making test-client-id.txt in the Files app. Kept on this
    /// phone only (the same file, so the Files route still works), never in a build, never logged.
    private var testModeEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Test mode app ID (private)").font(.body.weight(.semibold))
            Text("Signs in with another launcher's app ID while this project has none of its own. Not for sharing, and it can stop working at any time. The ID stays on this phone. Saved here, it applies to the next sign-in. A build with its own app ID ignores it.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Image(systemName: "key.fill").foregroundStyle(.secondary)
                TextField("Paste the app ID", text: $idText)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .focused($idFocused)
                    .submitLabel(.done)
                    .onSubmit { saveID() }
                if !idText.isEmpty {
                    Button { idText = ""; idProblem = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear the field")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10).glassCapsule()
            if let idProblem {
                Text(idProblem).font(.footnote).foregroundStyle(Palette.red).fixedSize(horizontal: false, vertical: true)
            } else if let storedID {
                Text("Saved: \(masked(storedID)). \(idSaved ? "Applies to the next sign-in." : "")")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    if let s = UIPasteboard.general.string { idText = s.trimmingCharacters(in: .whitespacesAndNewlines); idProblem = nil }
                } label: { Label("Paste", systemImage: "doc.on.clipboard").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36) }
                    .secondaryAction().tint(brand)
                Button { saveID() } label: {
                    Label("Save", systemImage: "checkmark").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36)
                }
                .primaryAction().tint(brand)
                .disabled(idText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if storedID != nil {
                Button(role: .destructive) { clearID() } label: {
                    Text("Remove the saved ID").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36)
                }
                .secondaryAction().tint(Palette.red)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func masked(_ id: String) -> String {
        id.count <= 8 ? id : String(id.prefix(4)) + "..." + String(id.suffix(4))
    }

    private func saveID() {
        var problem: NSString? = nil
        if HZSetLegacyTestClientID(idText, &problem) {
            Haptics.success()
            idProblem = nil
            idSaved = true
            idText = ""
            idFocused = false
            storedID = HZLegacyTestClientID()
        } else {
            Haptics.warning()
            idProblem = (problem as String?) ?? "That ID could not be saved."
        }
    }

    private func clearID() {
        var problem: NSString? = nil
        _ = HZSetLegacyTestClientID(nil, &problem)
        Haptics.tap()
        idSaved = false
        idProblem = nil
        storedID = HZLegacyTestClientID()
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
