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
    private static var dismissing = false

    /// Starts. Once. Called from main() before the engine, so these observers are registered before winit's own:
    /// winit makes its window visible inside UIApplicationDidFinishLaunching, and notification observers run in the
    /// order they were added, so this cover is already up (same run loop pass, before any frame is drawn) when the
    /// engine's window becomes visible. The first version polled the main queue every 0.2 s instead, and the
    /// engine's black boot screen, in landscape, was on screen until the first poll found it.
    @objc public static func begin() {
        guard !begun else { return }
        begun = true
        let center = NotificationCenter.default
        // queue: nil runs the block synchronously on the posting thread (the main thread), in registration order.
        center.addObserver(forName: UIApplication.didFinishLaunchingNotification, object: nil, queue: nil) { _ in
            raise(first: true)
        }
        // winit makes its window key again when the app becomes active; the cover must be the key window, because
        // the key window's controller decides the orientation (portrait for the launcher).
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
            raise(first: false)
        }
        // winit's own launch handler runs right after ours and makes ITS window key (landscape only). Take key back
        // on the next run loop passes, for the first second, so the system settles the orientation on the portrait
        // launcher and not on the engine's window. Also the safety net if the launch notification already passed.
        for delay in [0.0, 0.05, 0.15, 0.3, 0.6, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { raise(first: false) }
        }
        // If nothing could be shown within 10 s, say so and switch the experiment off for the next open.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if cover == nil {
                horizon_ios_breadcrumb("overlay: no launcher window after 10 s")
                HZLauncherModel.shared()?.inProcessPlay = false
            }
        }
    }

    /// The launcher is up (or about to be).
    static var isPresented: Bool { cover != nil }

    /// Makes the cover (once) and keeps it the key window. Legacy single-window app (no scene manifest): a plain
    /// UIWindow, like the old launcher's, not tied to a scene.
    private static func raise(first: Bool) {
        if cover == nil {
            guard UIApplication.shared.applicationState != .background || first else { return }
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.windowLevel = UIWindow.Level.alert + 1       // above whatever winit shows, including its keyboard
            window.backgroundColor = HZTheme.background()
            let host = OverlayHost(rootView: RootView())
            host.view.backgroundColor = HZTheme.background()
            window.rootViewController = host
            cover = window
            // The saved System / Dark / Light choice, as the launcher window had it.
            window.overrideUserInterfaceStyle = HZTheme.appearance() == .dark ? .dark
                : HZTheme.appearance() == .light ? .light : .unspecified
            HZTheme.applyAppearanceToWindows()
            horizon_ios_breadcrumb(first ? "overlay: launcher window up at launch" : "overlay: launcher window up (late)")
        }
        guard let window = cover, !dismissing else { return }
        window.isHidden = false
        if !window.isKeyWindow { window.makeKeyAndVisible() }
        // The scene (if the system has made one) may start landscape because the engine's window asks for it.
        turn(window.windowScene, to: .portrait)
    }

    /// Play was accepted by the engine: turn the scene to landscape under the cover, then fade the cover away.
    @objc public static func dismiss() {
        guard let window = cover else { return }
        let scene = window.windowScene
        dismissing = true
        cover = nil
        turn(scene, to: .landscape)
        // The turn takes a moment; the cover stays until the scene is landscape (or 1.5 s, whichever is first), so the
        // portrait-to-landscape swap and the engine's first frames happen out of sight.
        waitForLandscape(scene, left: 15) {
            UIView.animate(withDuration: 0.3, animations: { window.alpha = 0 }) { _ in
                window.isHidden = true
                // Hiding a window does not stop what is in it: the SwiftUI tree (its glass layers, observers and
                // any running timer) stays alive under the game and keeps taking the main thread's time. Taking
                // the root controller away frees the whole launcher; nothing shows it again in this run.
                window.rootViewController = nil
                // And the things the launcher kept for speed: the backdrop bitmap, parsed descriptions, cached images.
                LauncherMemory.releaseAll()
                horizon_ios_breadcrumb("overlay: launcher dismissed and released, game on screen")
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
