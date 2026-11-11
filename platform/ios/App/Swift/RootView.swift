import SwiftUI
import UIKit

/// The launcher's tabs. On iOS 26 the system draws the floating glass tab bar by itself; before that it is the
/// ordinary tab bar. The launcher is portrait; the game is landscape (see LauncherHost).
struct RootView: View {
    @StateObject private var state = LauncherState()
    @ObservedObject private var prefs = Prefs.shared
    @State private var tab = Tab.play
    @State private var path: [PlayRoute] = []

    enum Tab: Hashable { case play, packs, settings }

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
                        case .diagnostics: HostedPage(title: "Diagnostics") { HZLauncherDiagnosticsController() }
                        }
                    }
            }
            .tabItem { Label("Play", systemImage: "play.circle.fill") }
            .tag(Tab.play)

            Hosted { HZLauncherMarketplaceController() }
                .tabItem { Label("Packs", systemImage: "shippingbox.fill") }
                .tag(Tab.packs)

            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(prefs.brand)
        .environment(\.brand, prefs.brand)
        .environment(\.brand2, prefs.brand2)
        .onAppear { state.refresh() }
        .onChange(of: tab) { _ in state.refresh() }
        .onChange(of: path) { _ in state.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in state.refresh() }
    }
}
