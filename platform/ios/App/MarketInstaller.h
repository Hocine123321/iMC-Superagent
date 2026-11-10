// Installing from the Horizon Marketplace (M14, step 3), with no UIKit. It follows the desktop's
// install path (launcher/src/browser/horizon.rs, install_version_guarded; the game's own copy in
// crates/horizon-client/src/mod_registry.rs):
//   * the file goes to <home>/horizon-mods/<id>.hmod (a mod), <home>/resourcepacks/<name> or
//     <home>/shaderpacks/<name>, where <home> is the game's folder (Documents/Horizon/home);
//   * it is downloaded to <home>/mod-browser/downloads first and only renamed into place after the
//     size and SHA-256 match the index, the file was not taken down, and the project is not signed;
//   * the install is recorded in <home>/mod-browser.json (the file the desktop launcher and the game
//     both read), and a mod is turned on in <home>/horizon-mods.txt as "mod.<id>:true".
//
// What it does NOT do, so no label may claim it:
//   * Signed projects are REFUSED. The minisign check (Ed25519 + BLAKE2b) is not written, and a signed
//     project must never be installed as if it were unsigned. Today that is 1 of 24 installable projects.
//   * The deep content check the desktop runs after the hash (`index::inspect`: the mod's manifest, a
//     shader pack's own checks, a resource pack's pack.mcmeta) is not repeated here. The phone checks
//     the container is a ZIP; the game checks the content when it reads it and shows a red reason on a
//     mod it cannot load. docs/IOS_MARKETPLACE.md lists this.
#import <Foundation/Foundation.h>
#import "MarketIndex.h"

NS_ASSUME_NONNULL_BEGIN

@interface HZInstalledEntry : NSObject
@property (nonatomic, copy) NSString *projectId, *title, *kind, *version, *file, *checksum;
@property (nonatomic, copy) NSString *verdict;   // "Unsigned" (a verified entry written by the desktop reads "Verified")
@end

@interface HZMarketInstaller : NSObject
// `home` is the game folder (<Documents>/Horizon/home), the one that holds options.txt.
- (instancetype)initWithHome:(NSString *)home;
@property (nonatomic, readonly) NSString *home;

// ---- Rules (pure, public so a test can read them) ----

// Why `project`'s `version` cannot be installed, or nil. Covers: kind, signed, revoked, host, name,
// size, and the registry file rules again (an installer that trusts the parser alone is one bug away).
+ (nullable NSString *)refusalFor:(HZMarketProject *)project version:(HZMarketVersion *)version index:(HZMarketIndex *)index;

// The path (relative to home) a file of this project goes to, or nil for a kind that has no folder.
+ (nullable NSString *)relativePathForProject:(HZMarketProject *)project version:(HZMarketVersion *)version;

// Whether `data` starts like a ZIP (a .hmod, .zip and .hshader are all ZIP containers). A file that
// does not is refused before it is placed.
+ (BOOL)looksLikeZipAtPath:(NSString *)path;

// Lowercase hex SHA-256 of a file, read in chunks. nil if unreadable.
+ (nullable NSString *)sha256OfFileAtPath:(NSString *)path;

// ---- The record on disk ----

- (NSArray<HZInstalledEntry *> *)installed;
- (nullable HZInstalledEntry *)installedEntryForProject:(NSString *)projectId;

// ---- Doing it ----

// Checks a downloaded file at `temp` and, if it passes, moves it into place and records it. Returns nil
// on success or a sentence for the player; `temp` is deleted either way. Pure disk work: no network.
- (nullable NSString *)placeDownloaded:(NSString *)temp project:(HZMarketProject *)project version:(HZMarketVersion *)version index:(HZMarketIndex *)index;

// Removes an installed project's file, its record and (for a mod) its "mod.<id>" line. Returns nil or a sentence.
- (nullable NSString *)removeProject:(NSString *)projectId;

// A mod's on/off line in horizon-mods.txt.
- (BOOL)isModEnabled:(NSString *)projectId;
- (nullable NSString *)setMod:(NSString *)projectId enabled:(BOOL)on;

// The folder downloads are staged in.
- (NSString *)stagingDirectory;
@end

NS_ASSUME_NONNULL_END
