import SwiftUI
import UIKit

/// The launcher's window, started from Objective-C (Launcher.m) instead of the old UIKit home.
@objc(HZLauncherHost)
public final class LauncherHost: NSObject {
    /// The root view controller for the launcher window.
    @objc public static func makeRoot() -> UIViewController {
        let host = UIHostingController(rootView: RootView())
        host.view.backgroundColor = HZTheme.background()
        return host
    }
}
