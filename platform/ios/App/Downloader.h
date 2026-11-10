// The downloader (M8b, step 2): fetches the files DownloadPlan lists, from Mojang, into the game
// folder, checking each file's size and SHA-1 and writing whole files only, so a stopped download
// resumes where it was. It does not decide which files (DownloadPlan), judge the disk (DownloadStore)
// or show anything (LauncherDownload).
//
// What it fetches, in order:
//   1. Mojang's version manifest (piston-meta.mojang.com), to find the 26.3 version file's address
//      and sha1; the version file itself, checked against that sha1;
//   2. the asset index named in the version file, checked against its sha1;
//   3. the plan: client jar, libraries, logging file, then the asset objects;
//   4. the server jar (the preparer needs it), from the same version file.
// Sign-in is NOT checked here: the screen asks HZMayDownload first, so this class can be tested on
// its own and the gate lives in one place.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HZDownloadPhase) {
    HZPhaseIdle,
    HZPhaseLooking,      // manifest, version file, asset index
    HZPhaseChecking,     // what is already on the phone
    HZPhaseDownloading,
    HZPhaseDone,
    HZPhaseFailed,
    HZPhaseCancelled,
};

@interface HZDownloadProgress : NSObject
@property (nonatomic) HZDownloadPhase phase;
@property (nonatomic) NSUInteger filesDone, filesTotal;            // files finished, kept ones included
@property (nonatomic) unsigned long long bytesDone, bytesTotal;    // bytes on the phone, of the whole set
@property (nonatomic, copy) NSString *message;                     // one plain line for the screen
@property (nonatomic, copy, nullable) NSString *error;             // set with HZPhaseFailed
@end

@interface HZDownloader : NSObject
// `root` is the game folder (<Documents>/Horizon/minecraft); `version` is "26.3".
- (instancetype)initWithRoot:(NSString *)root version:(NSString *)version;

// Runs to the end on a background queue and calls `progress` on the main queue (at most about four
// times a second, and on every phase change). Safe to call again after a failure or a cancel: files
// that are whole are kept, so it carries on.
- (void)startWithProgress:(void (^)(HZDownloadProgress *p))progress;
// Stops soon. Files already installed stay; a file in flight is dropped.
- (void)cancel;
@property (atomic, readonly) BOOL running;

// Test hook: the server jar is 62 MB and optional for a "just the game" check.
@property (nonatomic) BOOL includeServerJar;   // default YES

// Pure helpers, public so a test can read them.
// How many files may be in flight at once (small files dominate, so more than one).
+ (NSUInteger)concurrency;
// Seconds to wait before attempt `n` (1 is the first retry): 2, 4, 8, capped.
+ (NSTimeInterval)backoffForAttempt:(NSUInteger)n;
// Whether an HTTP status is worth retrying (server trouble, throttling), as against a hard no.
+ (BOOL)shouldRetryStatus:(NSInteger)status;
// The address of version `version` in the manifest JSON, and its sha1. nil if absent or not Mojang's.
+ (nullable NSDictionary<NSString *, NSString *> *)versionEntryIn:(NSData *)manifest version:(NSString *)version;
@end

NS_ASSUME_NONNULL_END
