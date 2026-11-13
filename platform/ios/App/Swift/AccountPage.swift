import SwiftUI
import UIKit

/// Everything about the Microsoft account: who is signed in, whether it owns Java Edition, the sign-in itself
/// (with its code, the page to open and the time left), and what the account is and is not used for.
/// The rules live in the Objective-C AccountClient/AccountModel; this only shows them.
@MainActor
final class AccountController: ObservableObject {
    enum Phase: Equatable { case idle, starting, code, checking }

    @Published var name: String? = nil
    @Published var uuid: String? = nil
    @Published var owns = false
    @Published var phase: Phase = .idle
    @Published var userCode = ""
    @Published var verificationURI = ""
    @Published var statusLine = ""
    @Published var secondsLeft = 0
    @Published var errorMessage: String? = nil
    @Published var checkNote: String? = nil
    @Published var lastChecked: Date? = nil

    private var code: HZDeviceCode?
    private var timer: Timer?

    var signedIn: Bool { name != nil }
    var testMode: Bool { HZSignInIsTestMode() }
    var configured: Bool { HZActiveClientID() != nil }

    init() { refresh() }

    func refresh() {
        let a = HZAccountStore.shared().account()
        name = a?.name
        uuid = a?.uuid
        owns = a?.owns ?? false
        let t = LauncherFile.number("accountChecked", default: 0)
        lastChecked = t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    // MARK: sign in

    func signIn() {
        errorMessage = nil
        phase = .starting
        statusLine = "Starting sign-in..."
        HZAccountClient.shared().requestDeviceCode { [weak self] code, error in
            Task { @MainActor in
                guard let self else { return }
                guard let code else { self.fail(error); return }
                self.code = code
                self.userCode = code.userCode
                self.verificationURI = code.verificationURI
                self.secondsLeft = Int(code.expiresIn)
                self.phase = .code
                self.statusLine = "Waiting for you to finish on the Microsoft page."
                UIPasteboard.general.string = code.userCode
                self.startTimer()
                HZAccountClient.shared().completeSign(in: code, status: { [weak self] line in
                    Task { @MainActor in if self?.code === code { self?.statusLine = line } }
                }, done: { [weak self] account, err in
                    Task { @MainActor in
                        guard let self, self.code === code else { return }   // cancelled or left: a late answer changes nothing
                        self.finishCode()
                        if account == nil { self.fail(err); return }
                        self.touchChecked()
                        self.refresh()
                        Haptics.success()
                    }
                })
            }
        }
    }

    func cancel() {
        HZAccountClient.shared().cancel()
        finishCode()
        refresh()
    }

    private func fail(_ message: String?) {
        finishCode()
        errorMessage = message ?? "Microsoft sign-in failed."
        Haptics.warning()
        refresh()
    }

    private func finishCode() {
        timer?.invalidate(); timer = nil
        code = nil
        phase = .idle
        userCode = ""
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.secondsLeft > 0 { self.secondsLeft -= 1 }
            }
        }
    }

    func copyCode() {
        UIPasteboard.general.string = userCode
        Haptics.success()
    }

    /// Only Microsoft's own page: the address came from a reply, so it is checked before it is opened.
    func openMicrosoft() {
        guard let url = URL(string: verificationURI), url.scheme == "https", let host = url.host,
              host == "www.microsoft.com" || host == "microsoft.com" || host.hasSuffix(".microsoft.com") || host.hasSuffix(".live.com")
        else { return }
        UIApplication.shared.open(url)
    }

    // MARK: the account

    func signOut() {
        HZAccountStore.shared().signOut()
        LauncherFile.set("accountChecked", "0")
        SkinService.forget()
        checkNote = nil
        refresh()
    }

    func recheck() {
        phase = .checking
        checkNote = nil
        HZAccountClient.shared().recheck { [weak self] reachable, owns, error in
            Task { @MainActor in
                guard let self else { return }
                self.phase = .idle
                if reachable {
                    self.touchChecked()
                    self.checkNote = owns ? "Microsoft and Mojang confirm this account owns Minecraft: Java Edition."
                                          : (error ?? "The services answered, and this account does not own Minecraft: Java Edition.")
                } else {
                    self.checkNote = "Could not reach Microsoft or Mojang" + (error.map { ": \($0)" } ?? ".") + " The last answer still stands."
                }
                self.refresh()
            }
        }
    }

    private func touchChecked() {
        LauncherFile.set("accountChecked", String(Int(Date().timeIntervalSince1970)))
    }
}

struct AccountPage: View {
    @StateObject private var c = AccountController()
    @Environment(\.brand) private var brand
    @Environment(\.brand2) private var brand2
    @State private var confirmSignOut = false
    @State private var headProblem: String? = nil

    var body: some View {
        Page("Account") {
            if c.phase == .code { codeCard }
            else if c.signedIn { profileCard }
            else { signInCard }

            if c.signedIn && c.phase != .code { signedInSections }
            if let error = c.errorMessage { errorCard(error) }
            if !c.signedIn || c.phase == .code { stepsCard }
            aboutCard
        }
        .onAppear { c.refresh() }
        .onDisappear { if c.phase == .code { c.cancel() } }
        .alert("Sign out?", isPresented: $confirmSignOut) {
            Button("Sign out", role: .destructive) { c.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The sign-in is removed from this phone. Game files already here keep working; downloading needs you to sign in again.")
        }
    }

    // MARK: signed in

    private var profileCard: some View {
        VStack(spacing: 16) {
            MinecraftHead(uuid: c.uuid, size: 96, onProblem: { headProblem = $0 })
            VStack(spacing: 6) {
                Text(c.name ?? "").font(.system(.title, design: .rounded).weight(.bold))
                StatusPill(kind: c.owns ? .ok : .warn, text: c.owns ? "Owns Java Edition" : "Ownership not confirmed")
            }
            if let why = headProblem, Prefs.shared.showHead {
                Text("No head shown: \(why)").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let uuid = c.uuid {
                Button {
                    UIPasteboard.general.string = formatted(uuid); Haptics.success()
                } label: {
                    Label(formatted(uuid), systemImage: "doc.on.doc").font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Copy the profile ID")
            }
        }
        .padding(22).frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 32, tint: brand.opacity(0.18))
    }

    private var signedInSections: some View {
        VStack(spacing: 16) {
            SectionLabel("Status")
            GlassGroup {
                RowLabel(symbol: c.owns ? "checkmark.seal.fill" : "exclamationmark.triangle.fill", tone: c.owns ? .ok : .warn,
                         title: "Minecraft: Java Edition",
                         detail: c.owns ? "This account can download the game." : "Check again, or sign in with another account.",
                         chevron: false)
                Sep()
                RowLabel(symbol: "clock.fill", tone: .brand, title: "Last checked",
                         detail: c.lastChecked.map { Self.dateText($0) } ?? "Not since the sign-in was made.", chevron: false)
                Sep()
                RowLabel(symbol: "lock.fill", tone: .brand2, title: "Sign-in storage",
                         detail: "In this phone's Keychain, for this phone only.", chevron: false)
                Sep()
                RowLabel(symbol: "gamecontroller.fill", tone: .brand, title: "In the game",
                         detail: "The game starts as your profile, \(c.name ?? ""). Without a sign-in it starts offline.", chevron: false)
            }
            if let note = c.checkNote {
                Text(note).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
            }
            HStack(spacing: 12) {
                Button { Haptics.tap(); c.recheck() } label: {
                    HStack(spacing: 8) {
                        if c.phase == .checking { ProgressView() }
                        Text(c.phase == .checking ? "Checking..." : "Check again").font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                }
                .primaryAction().tint(brand).disabled(c.phase == .checking)
                Button(role: .destructive) { confirmSignOut = true } label: {
                    Text("Sign out").font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                }
                .secondaryAction().tint(brand2)
            }
            Button { c.signOutAndSignIn() } label: {
                Text("Use a different account").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 40)
            }
            .secondaryAction()
        }
    }

    // MARK: not signed in

    private var signInCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 54)).foregroundStyle(brand)
            VStack(spacing: 6) {
                Text(headline).font(.system(.title2, design: .rounded).weight(.bold)).multilineTextAlignment(.center)
                Text(subline).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { Haptics.tap(); c.signIn() } label: {
                HStack(spacing: 8) {
                    if c.phase == .starting { ProgressView() }
                    Label(c.phase == .starting ? "Starting..." : "Sign in with Microsoft", systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .primaryAction().tint(brand).controlSize(.large)
            .disabled(!c.configured || c.phase == .starting)
        }
        .padding(22).frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 32, tint: brand.opacity(0.18))
    }

    private var headline: String {
        if c.testMode { return "Not signed in (test mode)" }
        return c.configured ? "Not signed in" : "Sign-in is not set up yet"
    }
    private var subline: String {
        if c.testMode {
            return "Test mode: signing in with another launcher's app ID, set on this phone only. It can stop working at any time and is not for sharing. Sign in with the Microsoft account that owns Minecraft: Java Edition."
        }
        return c.configured ? "Sign in with the Microsoft account that owns Minecraft: Java Edition." : HZSignInNotConfigured
    }

    private var codeCard: some View {
        VStack(spacing: 16) {
            Text("Enter this code").font(.headline).foregroundStyle(.secondary)
            Button { c.copyCode() } label: {
                Text(c.userCode)
                    .font(.system(size: 44, weight: .heavy, design: .monospaced)).tracking(4)
                    .minimumScaleFactor(0.5).lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sign-in code \(c.userCode.map { String($0) }.joined(separator: " ")). Tap to copy.")
            Text("It is copied for you. Tap it to copy again.").font(.footnote).foregroundStyle(.secondary)
            Button { Haptics.tap(); c.openMicrosoft() } label: {
                Label("Open \(c.verificationURI.replacingOccurrences(of: "https://", with: ""))", systemImage: "safari.fill")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .primaryAction().tint(brand).controlSize(.large)
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(c.statusLine).font(.subheadline).foregroundStyle(.secondary)
                }
                Text("The code works for \(timeText(c.secondsLeft)) more.").font(.footnote).foregroundStyle(.tertiary)
            }
            Button("Cancel", role: .cancel) { c.cancel() }.secondaryAction()
        }
        .padding(22).frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 32, tint: brand2.opacity(0.18))
    }

    private func errorCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: "exclamationmark.triangle.fill", tone: .brand2, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text("Could not sign in").font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22, tint: brand2.opacity(0.2))
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How signing in works").font(.headline)
            step(1, "Tap Sign in. The app asks Microsoft for a one-time code and copies it.")
            step(2, "Open the Microsoft page, paste the code and sign in with the account that owns Minecraft.")
            step(3, "Come back here. The app checks with Mojang that the account owns Java Edition.")
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 24)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.footnote.weight(.bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Circle().fill(brand))
            Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What the account is for").font(.headline)
            Text("Signing in is needed only to download the game; playing files already on this phone never asks for it. When you are signed in, the game plays as your profile. The sign-in stays on this phone, in the Keychain, and is removed when you sign out. The app never sees your Microsoft password: you type it on Microsoft's own page.")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 24)
    }

    // MARK: text

    private func formatted(_ hex: String) -> String {
        let h = hex.replacingOccurrences(of: "-", with: "")
        guard h.count == 32 else { return hex }
        let a = Array(h)
        func part(_ r: Range<Int>) -> String { String(a[r]) }
        return [part(0..<8), part(8..<12), part(12..<16), part(16..<20), part(20..<32)].joined(separator: "-")
    }

    private func timeText(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        return m > 0 ? "\(m) min \(s) s" : "\(s) s"
    }

    private static func dateText(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}

extension AccountController {
    /// Signs out and starts a new sign-in straight away.
    func signOutAndSignIn() {
        signOut()
        signIn()
    }
}
