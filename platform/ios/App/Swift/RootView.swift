import SwiftUI
import UIKit

/// The launcher's tabs. On iOS 26 the system draws the floating glass tab bar by itself; before that it is the
/// ordinary tab bar. The launcher is portrait; the game is landscape (see LauncherHost).
struct RootView: View {
    @StateObject private var state = LauncherState()
    @ObservedObject private var look = AccentLook.shared
    @State private var tab = Tab.play
    @State private var path: [PlayRoute] = []

    enum Tab: Hashable { case play, packs, controls, settings }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $path) {
                PlayTab(state: state, open: { path.append($0) })
                    .navigationBarHidden(true)
                    .navigationDestination(for: PlayRoute.self) { route in
                        switch route {
                        case .download: DownloadPage()
                        case .files: GameFilesPage()
                        case .account: AccountPage()
                        case .diagnostics: DiagnosticsPage(start: .logs)
                        }
                    }
            }
            .tabItem { Label("Play", systemImage: "play.circle.fill") }
            .tag(Tab.play)

            MarketplaceTab()
                .tabItem { Label("Packs", systemImage: "shippingbox.fill") }
                .tag(Tab.packs)

            ControlsTab()
                .tabItem { Label("Controls", systemImage: "gamecontroller.fill") }
                .tag(Tab.controls)

            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(look.brand)
        .environment(\.brand, look.brand)
        .environment(\.brand2, look.brand2)
        .environment(\.brandDeep, look.brandDeep)
        .environment(\.brand2Deep, look.brand2Deep)
        .environment(\.lightweight, look.lightweight)
        .onAppear { state.refresh() }
        .onChange(of: tab) { _ in state.refresh() }
        .onChange(of: path) { _ in state.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in state.refresh() }
        // Settings are written to launcher.txt a moment after they change; make sure none is left behind.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in HZTheme.flushSettings() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in HZTheme.flushSettings() }
    }
}
