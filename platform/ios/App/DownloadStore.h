// The disk side of the download (M8b, step 2): is a file already here and whole, what is its SHA-1,
// where does a half-finished download live, and how does a finished one become the real file.
// No network and no UIKit, so every rule can be read (and mirrored in a test) on its own.
//
// The rules, which make an interrupted download resume instead of restart:
//   * A file is written under "<name>.part" and moved to its real name only after its size and
//     SHA-1 match what Mojang lists. A real name therefore always holds a whole file.
//   * On the next run a file at its real name with the listed size is hashed and kept when it
//     matches; a file that does not match is deleted and fetched again. A ".part" is never trusted:
//     it is deleted (a URLSession download task cannot be appended to safely).
//   * Paths come from DownloadPlan, which has already refused anything that could leave the folder;
//     this class checks again that the final path is inside the root (a symlink cannot lead out).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HZFileState) {
    HZFileMissing,   // nothing usable at the real name: fetch it
    HZFileComplete,  // the real name holds a whole, verified file: skip it
};

@interface HZDownloadStore : NSObject
// `root` is the game folder, for example <Documents>/Horizon/minecraft.
- (instancetype)initWithRoot:(NSString *)root;
@property (nonatomic, readonly) NSString *root;

// The absolute path for a plan path, or nil when it would land outside `root`.
- (nullable NSString *)absolutePathFor:(NSString *)relativePath;

// Looks at the disk. A file that is there but wrong (size or hash) is deleted and reported missing.
// Hashing a big file takes time: call off the main thread.
- (HZFileState)stateOfPath:(NSString *)relativePath size:(unsigned long long)size sha1:(NSString *)sha1;

// Moves a finished download into place after checking it. `temp` is the file URLSession wrote.
// Returns nil on success, or a message (the temp file is deleted either way).
- (nullable NSString *)installDownloaded:(NSString *)temp
                                  toPath:(NSString *)relativePath
                                    size:(unsigned long long)size
                                    sha1:(NSString *)sha1;

// Deletes every leftover "*.part" under `root` (an earlier run was stopped). Returns how many.
- (NSUInteger)removePartialFiles;

// Lowercase hex SHA-1 of a file, read in chunks (no whole-file load). nil if it cannot be read.
+ (nullable NSString *)sha1OfFileAtPath:(NSString *)path;
// Whether `s` is `n` lowercase hex digits.
+ (BOOL)isHex:(NSString *)s length:(NSUInteger)n;
// Free bytes on the volume holding `path` (important-usage capacity), 0 if unknown.
+ (unsigned long long)freeBytesAt:(NSString *)path;
@end

NS_ASSUME_NONNULL_END
