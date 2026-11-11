#import "EngineOverlay.h"
#import "AccountClient.h"
#import "AccountStore.h"
#import "Horizon-Swift.h"   // HZEngineOverlay (App/Swift/EngineOverlay.swift)

static BOOL gInProcess = NO;
void HZSetInProcessPlay(BOOL on) { gInProcess = on; }
BOOL HZIsInProcessPlay(void) { return gInProcess; }

void HZEngineOverlayStart(void) {
    // main() is on the main thread, before UIApplicationMain (which winit calls inside horizon_ios_main).
    // The overlay waits for the application to exist and for winit's window to have a root controller.
    dispatch_async(dispatch_get_main_queue(), ^{
        [HZEngineOverlay begin];
        // What the launcher's own delegate does once per run (Launcher.m): renew a saved sign-in in the background,
        // so the Minecraft token written at Play is not a day old. Silent; a network failure keeps the last answer.
        if ([[HZAccountStore shared] account]) [[HZAccountClient shared] recheck:^(BOOL reachable, BOOL owns, NSString *error) {}];
    });
}
