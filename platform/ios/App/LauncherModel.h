// What the launcher knows about the phone's Horizon installation, with no user interface.
// Kept apart from the screens so the rules (is the game folder usable, how big is it, what
// does Play do) are in one place and can be read without UIKit.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, HZFilesState) {
    HZFilesMissing,   // no horizon-resources.json
    HZFilesDamaged,   // the engine would refuse it (same three rules as damaged_prepared)
    HZFilesReady,
};

@interface HZLauncherModel : NSObject
// <Documents>/Horizon, the folder the Files app shows.
@property (nonatomic, readonly) NSString *root;
@property (nonatomic, readonly) NSString *resources;   // root/resources, what the engine reads
@property (nonatomic, readonly) NSString *home;        // root/home, saves, options and logs

+ (instancetype)shared;

// Looks at the disk now. `problem` says why when the state is not ready.
- (HZFilesState)checkFiles:(NSString **)problem;
// Total bytes under the resources folder (walks it: call off the main thread for a big folder).
- (unsigned long long)resourcesSize;
// The number of entries directly inside resources.
- (NSUInteger)topLevelItemCount;

// The one-shot "start the game on the next launch" flag, kept as a file so it survives the app
// being closed. main.m reads it once and removes it.
- (BOOL)setStartGameFlag;
- (BOOL)consumeStartGameFlag;

// "Open straight into the game": a setting kept in <root>/launcher.txt, which main.m reads before
// the engine starts (the engine's own settings live in home/ and are read much later).
@property (nonatomic) BOOL opensGameDirectly;

// "Play without closing the app" (M24 stage 3, docs/IN_PROCESS_PLAY_DESIGN.md): launcher.txt line
// `inProcessPlay:true`. OFF unless the file says so. When on, main.m starts the engine at launch, the
// engine waits for Play, and the launcher is shown over the engine's window. Off keeps the relaunch.
@property (nonatomic) BOOL inProcessPlay;
// Whether this open should skip the launcher and start the game. Call it before the crash
// reporter is installed, because that rewrites the evidence this reads. False when the setting is
// off, the files are not usable, the file <root>/open-launcher exists (delete it to go back), or
// the previous run crashed (the launcher opens once so Diagnostics is one tap away).
- (BOOL)shouldSkipLauncher;

// Moves the contents of a picked folder into resources, replacing what is there. Completion runs
// on the main thread with nil on success.
- (void)importFolderAtURL:(NSURL *)source
               completion:(void (^)(NSError *error))completion
                 progress:(void (^)(double fraction, NSString *file))progress;

// The text of the newest crash report and the game's log, for the Diagnostics screen.
- (NSString *)crashReportText;
- (NSString *)gameLogText;
- (NSArray<NSURL *> *)diagnosticFiles;   // files worth sharing, those that exist
@end
