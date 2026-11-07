// The app's entry point. winit's EventLoop::run_app calls UIApplicationMain itself, so this
// file declares no UIApplicationDelegate: it only hands the process over to Rust.
#import <Foundation/Foundation.h>

// Exported by libhorizon_ios_bridge.a (horizon/platform/ios-bridge).
extern void horizon_ios_main(void);

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Rust's std::env::args() reads the process arguments, so the game's options go there.
        // The game keeps everything under the app container's Library/Application Support/horizon
        // (the engine's default data folder on Apple platforms), so no --home is needed.
        horizon_ios_main();
    }
    return 0;
}
