import SwiftUI
import UIKit

/// The third tab. A plain list of places, each opening an existing screen. The old "..." menu on the home screen
/// held File manager, Diagnostics and About; they live here now so nothing became unreachable.
struct SettingsTab: View {
    enum Route: Hashable { case preferences, fileManager, files, diagnostics, about }
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    row("Preferences", "slider.horizontal.3", "Appearance, background, Marketplace and start-up.", .preferences)
                }
                Section("Library") {
                    row("File manager", "folder.badge.gearshape", "Browse, add and delete files inside the Horizon folder.", .fileManager)
                    row("Game files", "shippingbox", "Import, check or replace the game files.", .files)
                }
                Section("Help") {
                    row("Diagnostics", "stethoscope", "Crash report, game log and device checks.", .diagnostics)
                    row("About", "info.circle", "Version, licences and credits.", .about)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Backdrop())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .preferences: HostedPage(title: "Preferences") { HZLauncherSettingsController() }
                case .fileManager: HostedNav(title: "File manager") { HZLauncherFileManagerController(path: "") }
                case .files: HostedPage(title: "Game files") { HZLauncherFilesController() }
                case .diagnostics: HostedPage(title: "Diagnostics") { HZLauncherDiagnosticsController() }
                case .about: HostedPage(title: "About") { HZLauncherAboutController() }
                }
            }
        }
    }

    private func row(_ title: String, _ symbol: String, _ detail: String, _ route: Route) -> some View {
        Button { path.append(route) } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Look.accent).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
