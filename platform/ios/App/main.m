// The app's entry point. winit's EventLoop::run_app calls UIApplicationMain itself, so this
// file declares no UIApplicationDelegate: it only hands the process over to Rust.
//
// The engine reads its options from the process arguments (`std::env::args()`), and its
// defaults assume a desktop: resources next to the executable (here a read-only app bundle)
// or `.local/horizon-client/26.3` relative to the working directory (here `/`). So the paths
// are worked out here, from the sandbox, and passed as arguments.
#import <Foundation/Foundation.h>
#import "GameSession.h"
#import "Diagnostics.h"
#import "CrashReporter.h"
#import "SessionLog.h"
#import "Launcher.h"
#import "LauncherModel.h"
#import "EngineOverlay.h"
#include <crt_externs.h>   // _NSGetArgc / _NSGetArgv (iOS 13 SDK and later)
#include <stdlib.h>
#include <string.h>

// Exported by libhorizon_ios_bridge.a (horizon/platform/ios-bridge).
extern void horizon_ios_main(void);
// Play without closing the app (horizon/platform/ios-bridge). Only used when launcher.txt says inProcessPlay:true.
extern void horizon_ios_arm_hold(void);

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

        // "Open straight into the game" is decided first: it reads the last run's crash report,
        // which the crash reporter below replaces.
        BOOL skipLauncher = [[HZLauncherModel shared] shouldSkipLauncher];

        // Before anything else can fail: a native crash writes Documents/Horizon/crash.txt.
        HorizonInstallCrashReporter(root);
        horizon_ios_breadcrumb("main: crash reporter installed");

        // A timeline of memory, heat and battery in Documents/Horizon/session-log.csv, for the
        // benchmark work (M6, M7). Local only; the launcher's Share button hands it over.
        HorizonStartSessionLog(root);

        // Writes Documents/Horizon/diagnostics.txt: device, entitlements, JIT state, runtime present.
        // Read-only checks, run before the engine; see Diagnostics.m.
        HorizonWriteDiagnostics(root);

        // Play without closing the app (M24 stage 3, OFF unless launcher.txt says inProcessPlay:true): the
        // engine starts now, shows its window, and waits; the launcher is presented over that window
        // (EngineOverlay.swift) and Play lets the engine load, in this same process. The engine's
        // arguments are the ones below, without a session file: the signed-in account is written when
        // Play is pressed, because the engine refuses a session file older than two minutes.
        BOOL inProcess = [[HZLauncherModel shared] inProcessPlay];
        if (inProcess) {
            horizon_ios_breadcrumb("main: in-process play, engine starts and waits for Play");
            HZSetInProcessPlay(YES);
        }

        // The app is a launcher first. The game is a separate run of the app (winit's EventLoop
        // cannot start after UIApplicationMain), so Play leaves a one-shot flag and the next open
        // starts the game. Without the flag, or without usable game files, the launcher opens.
        // The check is the engine's own, so a folder the engine would refuse never reaches it.
        BOOL startGame = [[HZLauncherModel shared] consumeStartGameFlag] || skipLauncher;
        NSString *why = nil;
        if (!inProcess && (!startGame || [[HZLauncherModel shared] checkFiles:&why] != HZFilesReady)) {
            horizon_ios_breadcrumb(startGame ? "main: start flag set but the files are not usable, launcher"
                                             : "main: opening the launcher");
            return HorizonRunLauncher(argc, argv);
        }

        // The engine's game folder (saves, servers.dat, packs, mods) is its working directory,
        // which the desktop launcher sets. An iOS app starts in "/", which is read-only.
        [fm changeCurrentDirectoryPath:home];

        // The signed-in account, if there is one, becomes the game's account: its profile name, UUID
        // and token, through the engine's session file (GameSession.h). Written now, not earlier,
        // because the engine refuses a file older than two minutes, and it deletes the file as it
        // reads it. No account, or a file that cannot be written safely, means the game starts
        // offline as before. This never stops the game from starting.
        HZRemoveStaleGameSession(root);
        // In-process the file is written when Play is pressed (it may be minutes after launch).
        NSString *session = inProcess ? nil : HZWriteGameSession(root);
        if (!inProcess) {
            HZNoteGameSession(root, session != nil);
            horizon_ios_breadcrumb(session ? "main: signed-in account handed to the game"
                                           : "main: no account for the game, offline");
        }

        // A new argv: the program name, then ours, then anything the system passed (a debugger's,
        // or a launch argument from a developer's scheme).
        // In-process the path is always passed: the file does not exist yet, and the engine reads it when
        // it loads (after Play). A missing file means offline, exactly as with no account.
        NSString *sessionPath = inProcess ? [root stringByAppendingPathComponent:@"game-session.json"] : session;
        const char *extra[] = { "--resources", resources.fileSystemRepresentation,
                                "--home", home.fileSystemRepresentation,
                                "--session-file", sessionPath ? sessionPath.fileSystemRepresentation : "" };
        int extras = sessionPath ? 6 : 4;
        int n = 1 + extras + (argc > 1 ? argc - 1 : 0);
        char **args = calloc((size_t)n + 1, sizeof(char *));
        int i = 0;
        args[i++] = argv[0];
        for (int k = 0; k < extras; k++) args[i++] = strdup(extra[k]);
        for (int k = 1; k < argc; k++) args[i++] = argv[k];
        args[i] = NULL;

        // Rust's std::env::args() reads `_NSGetArgc()` and `_NSGetArgv()` each time it is called
        // on Apple platforms (library/std/src/sys/args/unix.rs, "expected that it's only modified
        // in main / before other code runs"), so replacing them here is seen by the engine.
        // This leans on that std behaviour: older Rust copied NSProcessInfo.arguments instead.
        // The new array is never freed: it must outlive the game, which never returns.
        *_NSGetArgc() = n;
        *_NSGetArgv() = args;

        if (inProcess) {
            horizon_ios_arm_hold();                 // the engine's loader waits for Play
            HZEngineOverlayStart();                 // presents the launcher over winit's window
        }
        horizon_ios_breadcrumb("main: handing over to the engine");
        horizon_ios_main();
    }
    return 0;
}
