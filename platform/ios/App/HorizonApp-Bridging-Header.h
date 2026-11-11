// What Swift can see of the Objective-C launcher. Only the pieces the SwiftUI shell calls.
#import "LauncherModel.h"
#import "LauncherPrefs.h"
#import "LauncherTheme.h"
#import "AccountStore.h"
#import "AccountModel.h"
#import "CrashReporter.h"
#import "LauncherDownload.h"
#import "LauncherMarketplace.h"
#import "LauncherSettings.h"
#import "LauncherFileManager.h"
#import "LauncherAccount.h"
#import "LauncherDiagnostics.h"
#import "LauncherFiles.h"
#import "EngineOverlay.h"
#import "GameSession.h"
#import "AccountClient.h"
#import "Downloader.h"
#import "DownloadRate.h"

#include <stdbool.h>
// Play without closing the app (horizon/platform/ios-bridge, libhorizon_ios_bridge.a).
extern bool horizon_ios_play(void);
extern int horizon_ios_hold_state(void);
