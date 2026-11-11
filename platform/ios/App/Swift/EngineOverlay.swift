import SwiftUI
import UIKit

/// Presents the launcher over winit's window while the engine waits for Play (M24 stage 3, flag inProcessPlay).
///
/// The engine owns the UIWindow and its root view controller. This only presents a full-screen controller from the
/// topmost one, and dismisses it on Play. Nothing here is tested on a device: the timing of winit creating its window
/// (so the bounded retry), the orientation change from the landscape window to the portrait launcher, and the
/// dismissal are the three things to look at on the phone.
@objc(HZEngineOverlay)
public final class EngineOverlay: NSObject {
    private static var presented: UIViewController?
    private static var begun = false

    /// Starts looking for winit's window. Once.
    @objc public static func begin() {
        guard !begun else { return }
        begun = true
        attempt(left: 100)   // 100 x 0.2 s = 20 s
    }

    /// The launcher is up (or about to be).
    static var isPresented: Bool { presented != nil }

    private static func attempt(left: Int) {
        guard let top = topController(), top.view.window != nil else {
            if left > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { attempt(left: left - 1) }
            } else {
                // The window never appeared. Do not leave the player on a black screen with a waiting engine: the
                // launcher itself would be gone, so say so in the log and let the engine's own screen show.
                horizon_ios_breadcrumb("overlay: winit's window never appeared, no launcher")
                // Switch the experiment off so the next open is the normal launcher, where Settings can reach it.
                HZLauncherModel.shared()?.inProcessPlay = false
            }
            return
        }
        guard presented == nil else { return }
        let host = OverlayHost(rootView: RootView())
        host.view.backgroundColor = HZTheme.background()
        host.modalPresentationStyle = .fullScreen
        host.modalPresentationCapturesStatusBarAppearance = true
        presented = host
        // The saved System / Dark / Light choice, as the launcher window had it.
        HZTheme.applyAppearanceToWindows()
        top.present(host, animated: false) {
            turn(host.view.window?.windowScene, to: .portrait)
            horizon_ios_breadcrumb("overlay: launcher presented over the engine's window")
        }
    }

    /// Play was accepted by the engine: take the launcher away and turn the scene to landscape for the game.
    @objc public static func dismiss() {
        guard let host = presented else { return }
        let scene = host.view.window?.windowScene
        presented = nil
        host.dismiss(animated: true) {
            turn(scene, to: .landscape)
            horizon_ios_breadcrumb("overlay: launcher dismissed, game on screen")
        }
    }

    /// The view controller to present from: the top of the key window of the foreground scene.
    private static func topController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let window = windows.first(where: \.isKeyWindow) ?? windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
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

/// Portrait for the launcher; the engine's own controller is landscape only (A7), and a presented controller's
/// mask is what the system asks while it is on top.
private final class OverlayHost: UIHostingController<RootView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }
}
