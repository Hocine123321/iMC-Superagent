// The app's entry point. winit's EventLoop::run_app calls UIApplicationMain itself, so this
// file declares no UIApplicationDelegate: it only hands the process over to Rust.
//
// The engine reads its options from the process arguments (`std::env::args()`), and its
// defaults assume a desktop: resources next to the executable (here a read-only app bundle)
// or `.local/horizon-client/26.3` relative to the working directory (here `/`). So the paths
// are worked out here, from the sandbox, and passed as arguments.
#import <Foundation/Foundation.h>
#include <crt_externs.h>   // _NSGetArgc / _NSGetArgv (iOS 13 SDK and later)
#include <stdlib.h>
#include <string.h>

// Exported by libhorizon_ios_bridge.a (horizon/platform/ios-bridge).
extern void horizon_ios_main(void);

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        // Documents is shown in the Files app (UIFileSharingEnabled), so the player can copy a
        // prepared resource folder into "Horizon/resources" there. Saves, logs and settings
        // live in "Horizon/home" beside it.
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *root = [docs stringByAppendingPathComponent:@"Horizon"];
        NSString *resources = [root stringByAppendingPathComponent:@"resources"];
        NSString *home = [root stringByAppendingPathComponent:@"home"];
        [fm createDirectoryAtPath:resources withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:home withIntermediateDirectories:YES attributes:nil error:nil];

        // The engine's game folder (saves, servers.dat, packs, mods) is its working directory,
        // which the desktop launcher sets. An iOS app starts in "/", which is read-only.
        [fm changeCurrentDirectoryPath:home];

        // A new argv: the program name, then ours, then anything the system passed (a debugger's,
        // or a launch argument from a developer's scheme).
        const char *extra[] = { "--resources", resources.fileSystemRepresentation,
                                "--home", home.fileSystemRepresentation };
        int n = 1 + 4 + (argc > 1 ? argc - 1 : 0);
        char **args = calloc((size_t)n + 1, sizeof(char *));
        int i = 0;
        args[i++] = argv[0];
        for (int k = 0; k < 4; k++) args[i++] = strdup(extra[k]);
        for (int k = 1; k < argc; k++) args[i++] = argv[k];
        args[i] = NULL;

        // Rust's std::env::args() reads `_NSGetArgc()` and `_NSGetArgv()` each time it is called
        // on Apple platforms (library/std/src/sys/args/unix.rs, "expected that it's only modified
        // in main / before other code runs"), so replacing them here is seen by the engine.
        // This leans on that std behaviour: older Rust copied NSProcessInfo.arguments instead.
        // The new array is never freed: it must outlive the game, which never returns.
        *_NSGetArgc() = n;
        *_NSGetArgv() = args;

        horizon_ios_main();
    }
    return 0;
}
