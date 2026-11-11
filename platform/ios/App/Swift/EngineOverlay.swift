import SwiftUI
import UIKit

/// Puts the launcher over the engine while it waits for Play (M24 stage 3, flag inProcessPlay).
///
/// The engine owns the UIWindow and its root view controller, and while it waits for Play it paints its own black
/// "Horizon" boot screen. Presenting the launcher from that window's controller (the first version) let that screen
/// show for the polling gap at start, and again every time the scene turned between the landscape engine window and
/// the portrait launcher: the boot screen flashed in and out. So the launcher now has a window of its own, above the
/// engine's, created as soon as the application exists and filled with the launcher's background from its first frame.
/// The engine's window is never uncovered while the launcher is up; on Play the scene is turned to landscape under
/// the cover and the cover fades away only afterwards.
///
/// Nothing here is tested on a device except what the owner reports: the first version worked, with the flash.
@objc(HZEngineOverlay)
public final class EngineOverlay: NSObject {
    private static var cover: UIWindow?
    private static var begun = false
    private static var observer: NSObjectProtocol?

    /// Starts. Once. The window is made as soon as a window scene exists (winit has called UIApplicationMain by then).
    @objc public static func begin() {
        guard !begun else { return }
        begun = true
        attempt(left: 100)   // 100 x 0.1 s = 10 s
    }

    /// The launcher is up (or about to be).
    static var isPresented: Bool { cover != nil }

    private static func attempt(left: Int) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            if left > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { attempt(left: left - 1) }
            } else {
                horizon_ios_breadcrumb("overlay: no window scene appeared, no launcher")
                // Switch the experiment off so the next open is the normal launcher, where Settings can reach it.
                HZLauncherModel.shared()?.inProcessPlay = false
            }
            return
        }
        guard cover == nil else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level.alert + 1       // above whatever winit shows, including its keyboard
        window.backgroundColor = HZTheme.background()
        let host = OverlayHost(rootView: RootView())
        host.view.backgroundColor = HZTheme.background()
        window.rootViewController = host
        cover = window
        // The saved System / Dark / Light choice, as the launcher window had it.
        HZTheme.applyAppearanceToWindows()
        window.overrideUserInterfaceStyle = HZTheme.appearance() == .dark ? .dark
            : HZTheme.appearance() == .light ? .light : .unspecified
        window.isHidden = false
        window.makeKeyAndVisible()
        // The scene may start landscape (the engine's window asks for it); the launcher is portrait.
        turn(scene, to: .portrait)
        horizon_ios_breadcrumb("overlay: launcher window up over the engine's")
    }

    /// Play was accepted by the engine: turn the scene to landscape under the cover, then fade the cover away.
    @objc public static func dismiss() {
        guard let window = cover else { return }
        let scene = window.windowScene
        cover = nil
        turn(scene, to: .landscape)
        // The turn takes a moment; the cover stays until the scene is landscape (or 1.5 s, whichever is first), so the
        // portrait-to-landscape swap and the engine's first frames happen out of sight.
        waitForLandscape(scene, left: 15) {
            UIView.animate(withDuration: 0.3, animations: { window.alpha = 0 }) { _ in
                window.isHidden = true
                horizon_ios_breadcrumb("overlay: launcher dismissed, game on screen")
            }
        }
    }

    private static func waitForLandscape(_ scene: UIWindowScene?, left: Int, then done: @escaping () -> Void) {
        let landscape = scene?.interfaceOrientation.isLandscape ?? true
        if landscape || left == 0 { done(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { waitForLandscape(scene, left: left - 1, then: done) }
    }

    /// Asks the scene to turn now, rather than when the phone is next moved.
    private static func turn(_ scene: UIWindowScene?, to mask: UIInterfaceOrientationMask) {
        guard let scene else { return }
        for window in scene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                horizon_ios_breadcrumb("overlay: orientation request failed")
                NSLog("iMC orientation request failed: %@", error.localizedDescription)
            }
        }
    }
}

/// Portrait for the launcher; the engine's own controller is landscape only (A7), and the key window's controller is
/// the one the system asks while the cover is up.
private final class OverlayHost: UIHostingController<RootView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }
    override var prefersStatusBarHidden: Bool { false }
}
