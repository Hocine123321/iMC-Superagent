// The file manager's rules (M13), with no UIKit: what a folder holds, whether a path is allowed,
// what a delete would destroy, and the safe way to rename, create and delete. The screen
// (LauncherFileManager) only shows what this returns.
//
// The one rule that everything else rests on: nothing here ever touches a path outside the app's
// Horizon folder. A path is resolved (symlinks included) and compared with the folder's real path
// before any read or write; "..", absolute paths, backslashes and empty parts are refused first.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// How careful a delete must be.
typedef NS_ENUM(NSInteger, HZDeleteRisk) {
    HZDeleteOrdinary,   // a file or folder with nothing special in it
    HZDeleteWorld,      // under home/saves: the player's worlds, work that cannot be remade
    HZDeleteGameFiles,  // the prepared resources or the downloaded Minecraft: large, but can be got again
    HZDeleteAccount,    // the sign-in record: deleting it signs the player out (use the Account screen)
    HZDeleteForbidden,  // the Horizon folder itself: never
};

@interface HZFileEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *relativePath;   // from the Horizon folder, "/"-separated
@property (nonatomic) BOOL isFolder;
@property (nonatomic) unsigned long long size;        // files: bytes; folders: 0 until measured
@property (nonatomic, strong, nullable) NSDate *modified;
@end

@interface HZFileBrowser : NSObject
// `root` is <Documents>/Horizon.
- (instancetype)initWithRoot:(NSString *)root;
@property (nonatomic, readonly) NSString *root;

// The absolute, symlink-resolved path for a path relative to the root ("" is the root), or nil when it
// is not allowed or would resolve outside the root.
- (nullable NSString *)resolve:(NSString *)relativePath;

// The entries of a folder, folders first, then by name (case-insensitive). nil with `error` set if the
// path is not allowed or is not a folder. Hidden files (a leading dot) are listed too: the
// player's own folder has nothing to hide, and ".running" is useful evidence.
- (nullable NSArray<HZFileEntry *> *)listFolder:(NSString *)relativePath error:(NSString *_Nullable *_Nullable)error;

// Bytes under a path (walks it: call off the main thread). A symlink is counted as itself, never followed.
- (unsigned long long)sizeOf:(NSString *)relativePath;

// What deleting this would destroy, and the sentence to show before asking.
- (HZDeleteRisk)deleteRiskOf:(NSString *)relativePath;
+ (NSString *)warningForRisk:(HZDeleteRisk)risk name:(NSString *)name size:(unsigned long long)size;

// A valid new name for a file or folder: not empty, not "." or "..", no "/" or "\\" or control
// characters, at most 255 UTF-8 bytes. nil when fine, else the reason.
+ (nullable NSString *)problemWithName:(NSString *)name;

// The changes themselves. Each returns nil on success or a message. None follows a symlink out.
- (nullable NSString *)deletePath:(NSString *)relativePath;
- (nullable NSString *)renamePath:(NSString *)relativePath to:(NSString *)newName;
- (nullable NSString *)createFolderNamed:(NSString *)name inside:(NSString *)relativeFolder;

// The path of the parent folder ("" for the root), and the join of a folder and a name.
+ (NSString *)parentOf:(NSString *)relativePath;
+ (NSString *)join:(NSString *)folder name:(NSString *)name;
@end

NS_ASSUME_NONNULL_END
