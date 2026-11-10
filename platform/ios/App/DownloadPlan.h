// The download plan (M8b, step 1): which files to fetch from Mojang, and where to put them. No
// network, no UIKit, no disk: it reads the version JSON and the asset index the caller already has.
//
// It mirrors horizon/launcher/src/mojang.rs (the desktop download: client jar, libraries, logging
// file, then the asset objects, each with the size and sha1 Mojang lists, in the official launcher's
// layout), with one decision of its own: an iPhone counts as Linux on arm64 for the library rules,
// as horizon-prepare does (artifacts.rs rule_system(): "osx" on macOS, "windows" on Windows, "linux"
// for everything else). Without that, the plan would fetch no library at all, or the macOS set.
//
// Nothing here is downloaded or run yet. docs/IOS_DOWNLOAD_PLAN.md says what is and is not done.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// One file to fetch.
@interface HZDownloadFile : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *sha1;       // 40 lowercase hex characters
@property (nonatomic) unsigned long long size;    // bytes; 0 when Mojang lists none
@property (nonatomic, copy) NSString *path;       // relative to the game folder, never leaves it
@end

// The result of planning. `error` is set (and `files` empty) when the plan cannot be trusted.
@interface HZDownloadPlan : NSObject
@property (nonatomic, copy) NSArray<HZDownloadFile *> *game;     // client jar, libraries, logging file
@property (nonatomic, copy) NSArray<HZDownloadFile *> *assets;   // the sounds and other asset objects
@property (nonatomic) NSUInteger libraryCount;
@property (nonatomic, copy, nullable) NSString *error;

// Files and bytes in `game` plus `assets` (the number to show the player before downloading).
- (NSUInteger)fileCount;
- (unsigned long long)totalBytes;

// Plans the game files from the version JSON (`version` is its id, e.g. "26.3").
// Refuses: a download host that is not Mojang's, a path that could leave the folder, a library rule
// that asks about architecture, version or features (none exists in 26.3; if Mojang adds one the
// plan stops and names the library rather than guess), and a malformed hash.
+ (HZDownloadPlan *)planGameFromVersionJSON:(NSData *)json version:(NSString *)version;

// Adds `assets` from the asset index JSON (objects, each once, by hash).
- (BOOL)addAssetsFromIndexJSON:(NSData *)json error:(NSString *_Nullable *_Nullable)error;

// The hosts a download may come from. Anything else is refused.
+ (BOOL)isMojangHost:(NSString *)host;
// A path from Mojang's files, refused if it is absolute, has "..", a backslash or an empty part.
+ (nullable NSString *)safeRelativePath:(NSString *)path;
@end

NS_ASSUME_NONNULL_END
