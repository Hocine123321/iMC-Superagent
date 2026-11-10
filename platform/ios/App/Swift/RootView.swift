import SwiftUI
import UIKit

/// The three tabs. On iOS 26 the system draws the floating glass tab bar by itself; before that it is the
/// ordinary tab bar. The launcher is portrait; the game is landscape (see LauncherHost).
struct RootView: View {
    @StateObject private var state = LauncherState()
    @State private var tab = Tab.play
    @State private var path: [PlayRoute] = []

    enum Tab: Hashable { case play, packs, settings }
    enum PlayRoute: Hashable { case download, files, account }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $path) {
                PlayTab(state: state,
                        openDownload: { path.append(.download) },
                        openFiles: { path.append(.files) },
                        openAccount: { path.append(.account) })
                    .navigationBarHidden(true)
                    .navigationDestination(for: PlayRoute.self) { route in
                        switch route {
                        case .download: HostedPage(title: "Download") { HZLauncherDownloadController() }
                        case .files: HostedPage(title: "Game files") { HZLauncherFilesController() }
                        case .account: HostedPage(title: "Account") { HZLauncherAccountController() }
                        }
                    }
            }
            .tabItem { Label("Play", systemImage: "play.circle.fill") }
            .tag(Tab.play)

            Hosted { HZLauncherMarketplaceController() }
                .ignoresSafeArea()
                .tabItem { Label("Packs", systemImage: "shippingbox.fill") }
                .tag(Tab.packs)

            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(Look.accent)
        .onAppear { state.refresh() }
        .onChange(of: tab) { _ in state.refresh() }
        .onChange(of: path) { _ in state.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in state.refresh() }
    }
}
