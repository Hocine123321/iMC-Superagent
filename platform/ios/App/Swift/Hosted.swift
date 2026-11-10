import SwiftUI
import UIKit

/// Shows an existing UIKit screen inside SwiftUI. The screen keeps its own navigation bar and pushes,
/// so nothing it does changes. Each one is replaced by a SwiftUI page later (M24 stage 4).
struct Hosted: UIViewControllerRepresentable {
    let make: () -> UIViewController

    func makeUIViewController(context: Context) -> UINavigationController {
        let nav = UINavigationController(rootViewController: make())
        HZTheme.styleNavigationBar(nav.navigationBar)
        return nav
    }
    func updateUIViewController(_ nav: UINavigationController, context: Context) {}
}

/// A screen pushed over the Play tab (Download, Game files, Account).
struct HostedPage: View {
    let title: String
    let make: () -> UIViewController
    var body: some View {
        HostedPlain(make: make)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HostedPlain: UIViewControllerRepresentable {
    let make: () -> UIViewController
    func makeUIViewController(context: Context) -> UIViewController { make() }
    func updateUIViewController(_ vc: UIViewController, context: Context) {}
}

/// A screen that pushes other screens itself (File manager, Marketplace): it needs its own navigation controller.
/// The SwiftUI stack above it already shows the title and the back button, so this one hides its bar.
struct HostedNav: View {
    let title: String
    let make: () -> UIViewController
    var body: some View {
        HostedNavPlain(make: make)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HostedNavPlain: UIViewControllerRepresentable {
    let make: () -> UIViewController
    func makeUIViewController(context: Context) -> UINavigationController {
        let nav = UINavigationController(rootViewController: make())
        nav.setNavigationBarHidden(true, animated: false)
        return nav
    }
    func updateUIViewController(_ nav: UINavigationController, context: Context) {}
}
