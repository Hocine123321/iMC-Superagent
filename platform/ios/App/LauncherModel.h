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
