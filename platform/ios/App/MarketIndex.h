// The Horizon Marketplace index (M14, step 1): parsing and judging the registry's index.json, with no
// network and no UIKit. It follows horizon_mods::index (crates/horizon-mods/src/index.rs, schema 1,
// docs/api/mod-index.md) and is stricter in three places on purpose, because a phone has no second
// line of defence: a file may only come from the registry's own release host, an image only from the
// registry's own site, and a kind the phone cannot use is never offered for install.
//
// Nothing here downloads or installs anything. docs/IOS_MARKETPLACE.md says what is and is not done.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// What the phone can do with a project.
typedef NS_ENUM(NSInteger, HZMarketSupport) {
    HZMarketInstallable,    // content mod, resource pack, shader: can be installed by copying a file
    HZMarketNeedsDesktop,   // native mod: changes the game's source before it is compiled, so a phone cannot
    HZMarketNotYet,         // a kind the app has no installer for yet (modpack, shaderpack, datapack, unknown)
};

@interface HZMarketFile : NSObject
@property (nonatomic, copy) NSString *name;      // plain file name with the kind's extension
@property (nonatomic, copy) NSString *url;       // https, on the registry's release host
@property (nonatomic) unsigned long long size;
@property (nonatomic, copy) NSString *sha256;    // 64 lowercase hex
@property (nonatomic, copy, nullable) NSString *signature;   // minisign text, when the project has a key
@end

@interface HZMarketVersion : NSObject
@property (nonatomic, copy) NSString *version, *game, *published, *changelog;
@property (nonatomic, strong) HZMarketFile *file;
@end

@interface HZMarketProject : NSObject
@property (nonatomic, copy) NSString *projectId, *kind, *name, *summary, *details, *license, *source;
@property (nonatomic, copy) NSArray<NSString *> *authors, *categories, *screenshots;
@property (nonatomic, copy, nullable) NSString *icon;
@property (nonatomic, copy, nullable) NSString *key;      // minisign public key; nil = unsigned
@property (nonatomic) unsigned long long downloads, stars;
@property (nonatomic, copy) NSArray<HZMarketVersion *> *versions;   // newest first
@property (nonatomic) HZMarketSupport support;
@end

@interface HZMarketRevoked : NSObject
@property (nonatomic, copy) NSString *projectId, *reason, *date;
@property (nonatomic, copy, nullable) NSString *sha256;   // nil = every version of the project
@end

@interface HZMarketIndex : NSObject
@property (nonatomic, copy) NSString *generated;
@property (nonatomic, copy) NSArray<HZMarketProject *> *projects;
@property (nonatomic, copy) NSArray<HZMarketRevoked *> *revoked;

// The newest version of `project` for Minecraft `game` whose file was not taken down; nil if none.
- (nullable HZMarketVersion *)installableVersionOf:(HZMarketProject *)project game:(NSString *)game NS_SWIFT_NAME(installableVersion(of:game:));
// Why this project's file was taken down, or nil. `sha256` nil asks about the project as a whole.
- (nullable HZMarketRevoked *)revocationFor:(NSString *)projectId sha256:(nullable NSString *)sha256 NS_SWIFT_NAME(revocation(for:sha256:));
- (nullable HZMarketProject *)projectWithId:(NSString *)projectId NS_SWIFT_NAME(project(id:));

// Parses and checks. On a problem returns nil and sets `error` to a sentence for the player.
// A higher schema than 1 is refused with "update the app". A project that fails a rule makes the
// whole index fail (as the desktop's does): a half-trusted index is worse than the cached copy.
+ (nullable HZMarketIndex *)parse:(NSData *)json error:(NSString *_Nullable *_Nullable)error;

// The rules, public so a test can read them.
+ (BOOL)isValidProjectId:(NSString *)s;                  // [a-z0-9_]{1,64}
+ (BOOL)isPlainFileName:(NSString *)s;                   // no folder, no leading dot, [A-Za-z0-9._+-], <= 128
+ (BOOL)isLowerHex64:(NSString *)s;
+ (BOOL)isRegistryFileURL:(NSString *)url;               // https://github.com/horizon-rust/horizon-mods/releases/download/<tag>/<name>
+ (BOOL)isRegistryImageURL:(NSString *)url;              // https://horizon-rust.github.io/horizon-mods/...
+ (nullable NSString *)extensionForKind:(NSString *)kind;   // "hmod", "hshader", "zip"... nil = any
+ (HZMarketSupport)supportForKind:(NSString *)kind;
+ (unsigned long long)maxFileBytes;                      // 64 MiB, the registry's cap
+ (unsigned long long)maxIndexBytes;                     // what the app will read of index.json
@end

NS_ASSUME_NONNULL_END
