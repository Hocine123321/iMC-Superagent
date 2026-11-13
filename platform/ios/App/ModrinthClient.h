// Modrinth resource packs (the owner asked for them, 2026-11-10). Follows the desktop launcher
// (launcher/src/browser/modrinth.rs, download.rs, browser.rs): a search facet "resourcepack" for
// Minecraft 26.3, the newest listed version made for 26.3, its primary file, checked by SHA-512 (SHA-1
// if that is all it lists) and size, from cdn.modrinth.com only.
//
// Resource packs only. Modrinth's mods are Java mods the desktop ports with a JVM tool, which a phone does
// not have, and its shaders are not Horizon's format; neither is offered.
//
// The parsing has no network and no UIKit, so a test can read every rule.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HZModrinthFile : NSObject
@property (nonatomic, copy) NSString *name, *url;
@property (nonatomic) unsigned long long size;
@property (nonatomic, copy, nullable) NSString *sha512, *sha1;
@end

@interface HZModrinthVersion : NSObject
@property (nonatomic, copy) NSString *versionId, *number, *published;
@property (nonatomic, copy) NSArray<NSString *> *gameVersions;
@property (nonatomic, strong) HZModrinthFile *file;
@end

@interface HZModrinthProject : NSObject
@property (nonatomic, copy) NSString *projectId, *slug, *title, *summary, *author, *license;
@property (nonatomic, copy, nullable) NSString *iconURL;
@property (nonatomic) unsigned long long downloads;
@end

@interface HZModrinthClient : NSObject
// ---- Rules (pure) ----
+ (NSString *)apiBase;                          // https://api.modrinth.com/v2
+ (BOOL)isProjectId:(NSString *)s;              // Modrinth ids are 8 letters/digits
+ (BOOL)isCDNFileURL:(NSString *)url;           // https://cdn.modrinth.com/data/<id>/versions/<id>/<name>
+ (BOOL)isSafeFileName:(NSString *)name;        // the desktop's safe_name
+ (BOOL)isHex:(NSString *)s length:(NSUInteger)n;
// Percent-encoding for a query value (anything but A-Z a-z 0-9 - _ . ~).
+ (NSString *)encode:(NSString *)s;

// The search address for resource packs for `game`, most downloaded first (or by `text`).
+ (NSString *)searchURLForText:(NSString *)text game:(NSString *)game offset:(NSUInteger)offset limit:(NSUInteger)limit;
+ (NSString *)versionsURLForProject:(NSString *)projectId;

// Parses a search answer. Hits that fail a rule are dropped, never fatal. Returns nil with `error` when
// the answer is not the expected shape.
+ (nullable NSArray<HZModrinthProject *> *)parseSearch:(NSData *)json total:(NSUInteger *_Nullable)total error:(NSString *_Nullable *_Nullable)error;
// The newest listed version made for `game` with a usable file, or nil with `reason`.
+ (nullable HZModrinthVersion *)pickVersion:(NSData *)json game:(NSString *)game reason:(NSString *_Nullable *_Nullable)reason;
// Why this file cannot be installed, or nil: host, name, checksum, size.
+ (nullable NSString *)refusalForFile:(HZModrinthFile *)file;

// ---- Network (main queue callbacks) ----
- (void)searchText:(NSString *)text offset:(NSUInteger)offset completion:(void (^)(NSArray<HZModrinthProject *> *_Nullable projects, NSUInteger total, NSString *_Nullable error))done;
// The project's long description (Markdown, as the author wrote it), for the project page. The search reply only carries
// the one-line summary. Capped at 60,000 characters.
- (void)bodyOfProject:(HZModrinthProject *)project completion:(void (^)(NSString *_Nullable body, NSString *_Nullable error))done
    NS_SWIFT_NAME(body(of:completion:));
- (void)newestVersionOf:(HZModrinthProject *)project completion:(void (^)(HZModrinthVersion *_Nullable version, NSString *_Nullable error))done NS_SWIFT_NAME(newestVersion(of:completion:));
@end

NS_ASSUME_NONNULL_END
