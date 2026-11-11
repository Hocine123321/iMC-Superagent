// Play without closing the app (M24 stage 3, OFF unless launcher.txt says inProcessPlay:true).
// The engine (winit) owns its UIWindow; the SwiftUI launcher lives in a window of its own above it (so the engine's boot screen is never seen) and is taken away on Play.
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
// Call from main() before horizon_ios_main(): from then on the launcher is presented as soon as winit's
// window is on screen. Safe to call once.
void HZEngineOverlayStart(void);
// Tells the launcher that the process runs the engine in-process (LauncherState.play() branches on it).
void HZSetInProcessPlay(BOOL on);
BOOL HZIsInProcessPlay(void);
#ifdef __cplusplus
}
#endif
