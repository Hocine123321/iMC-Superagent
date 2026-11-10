#import "MarketInstaller.h"
#import <CommonCrypto/CommonDigest.h>

static NSString *const kManifest = @"mod-browser.json";
static NSString *const kModsList = @"horizon-mods.txt";
static NSString *const kModsDir = @"horizon-mods";

@implementation HZInstalledEntry
@end

@implementation HZMarketInstaller {
    NSString *_home;
}

- (instancetype)initWithHome:(NSString *)home {
    if ((self = [super init])) _home = [home copy];
    return self;
}
- (NSString *)home { return _home; }
- (NSString *)stagingDirectory { return [_home stringByAppendingPathComponent:@"mod-browser/downloads"]; }

#pragma mark - Rules

+ (NSString *)relativePathForProject:(HZMarketProject *)p version:(HZMarketVersion *)v {
    if ([p.kind isEqualToString:@"mod"]) return [NSString stringWithFormat:@"%@/%@.hmod", kModsDir, p.projectId];
    if ([p.kind isEqualToString:@"resourcepack"]) return [@"resourcepacks" stringByAppendingPathComponent:v.file.name];
    if ([p.kind isEqualToString:@"shader"]) return [@"shaderpacks" stringByAppendingPathComponent:v.file.name];
    return nil;
}

+ (NSString *)refusalFor:(HZMarketProject *)p version:(HZMarketVersion *)v index:(HZMarketIndex *)index {
    if (p.support == HZMarketNeedsDesktop) return [NSString stringWithFormat:@"%@ is a native mod: it changes the game's source before it is compiled, so it needs a desktop build.", p.name];
    if (p.support != HZMarketInstallable) return [NSString stringWithFormat:@"The app cannot install a %@ yet.", p.kind];
    if (![self relativePathForProject:p version:v]) return [NSString stringWithFormat:@"The app has no folder for a %@.", p.kind];
    // A signed project: the minisign check is not written, and skipping it would install a signed
    // project with less protection than the desktop gives it.
    if (p.key.length || v.file.signature.length) return [NSString stringWithFormat:@"%@ is signed by its author, and this app cannot check signatures yet, so it will not install it.", p.name];
    HZMarketRevoked *rev = [index revocationFor:p.projectId sha256:v.file.sha256];
    if (rev) return [NSString stringWithFormat:@"%@ was taken down by the registry: %@", p.name, rev.reason];
    if (![HZMarketIndex isRegistryFileURL:v.file.url]) return @"The file is not on the registry's release address.";
    if (![HZMarketIndex isPlainFileName:v.file.name]) return @"The file name is not a plain name.";
    if (![HZMarketIndex isLowerHex64:v.file.sha256]) return @"The index has no valid SHA-256 for this file.";
    if (v.file.size == 0 || v.file.size > [HZMarketIndex maxFileBytes]) return @"The file size in the index is outside what the app accepts.";
    NSString *ext = [HZMarketIndex extensionForKind:p.kind];
    if (ext && ![v.file.name.pathExtension isEqualToString:ext]) return [NSString stringWithFormat:@"A %@ file must end in .%@.", p.kind, ext];
    return nil;
}

+ (BOOL)looksLikeZipAtPath:(NSString *)path {
    NSFileHandle *h = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!h) return NO;
    NSData *head = [h readDataOfLength:4];
    [h closeFile];
    if (head.length < 4) return NO;
    const unsigned char *b = head.bytes;
    // PK\x03\x04 (a file), PK\x05\x06 (an empty archive).
    return b[0] == 'P' && b[1] == 'K' && ((b[2] == 3 && b[3] == 4) || (b[2] == 5 && b[3] == 6));
}

+ (NSString *)sha256OfFileAtPath:(NSString *)path {
    NSFileHandle *h = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!h) return nil;
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    while (YES) {
        @autoreleasepool {
            NSData *chunk = [h readDataOfLength:1 << 16];
            if (!chunk.length) break;
            CC_SHA256_Update(&ctx, chunk.bytes, (CC_LONG)chunk.length);
        }
    }
    [h closeFile];
    unsigned char out[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(out, &ctx);
    NSMutableString *hex = [NSMutableString stringWithCapacity:64];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", out[i]];
    return hex;
}

#pragma mark - The record (mod-browser.json, the desktop's format)

- (NSString *)manifestPath { return [_home stringByAppendingPathComponent:kManifest]; }

// The whole file as the desktop wrote it, entries untouched, so an entry this app does not understand
// (a Modrinth pack the desktop installed) is written back exactly as it was.
- (NSMutableArray<NSDictionary *> *)rawEntries {
    NSData *d = [NSData dataWithContentsOfFile:[self manifestPath]];
    id obj = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    NSArray *e = [obj isKindOfClass:[NSDictionary class]] ? obj[@"entries"] : nil;
    NSMutableArray *out = [NSMutableArray array];
    for (id x in [e isKindOfClass:[NSArray class]] ? e : @[]) if ([x isKindOfClass:[NSDictionary class]]) [out addObject:x];
    return out;
}

- (BOOL)saveRawEntries:(NSArray *)entries {
    NSData *d = [NSJSONSerialization dataWithJSONObject:@{@"entries": entries} options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    if (!d) return NO;
    [[NSFileManager defaultManager] createDirectoryAtPath:_home withIntermediateDirectories:YES attributes:nil error:nil];
    return [d writeToFile:[self manifestPath] atomically:YES];
}

- (NSArray<HZInstalledEntry *> *)installed {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *e in [self rawEntries]) {
        if (![e[@"source"] isEqual:@"horizon"]) continue;   // only what the Horizon registry installed
        NSString *file = e[@"file"];
        if (![file isKindOfClass:[NSString class]] || ![[self class] fileIsInsideInstallFolders:file]) continue;
        HZInstalledEntry *x = [HZInstalledEntry new];
        x.projectId = e[@"project"] ?: @"";
        x.title = e[@"title"] ?: x.projectId;
        x.kind = e[@"kind"] ?: @"";
        x.version = e[@"version"] ?: @"";
        x.file = file;
        x.checksum = e[@"checksum"] ?: @"";
        x.verdict = e[@"verdict"] ?: @"";
        [out addObject:x];
    }
    return out;
}

- (HZInstalledEntry *)installedEntryForProject:(NSString *)projectId {
    for (HZInstalledEntry *e in [self installed]) if ([e.projectId isEqualToString:projectId]) return e;
    return nil;
}

// An entry's file is only ever touched when it is plain names under one of the install folders (the
// list is a file in the game folder, which a modpack could have written; the desktop makes the same check).
+ (BOOL)fileIsInsideInstallFolders:(NSString *)file {
    NSArray *parts = [file componentsSeparatedByString:@"/"];
    if (parts.count < 2) return NO;
    if (![@[kModsDir, @"resourcepacks", @"shaderpacks", @"mods"] containsObject:parts[0]]) return NO;
    for (NSString *p in parts) if (!p.length || [p isEqualToString:@"."] || [p isEqualToString:@".."] || [p containsString:@"\\"]) return NO;
    return YES;
}

#pragma mark - horizon-mods.txt

- (NSString *)modsListPath { return [_home stringByAppendingPathComponent:kModsList]; }

- (BOOL)isModEnabled:(NSString *)projectId {
    NSString *text = [NSString stringWithContentsOfFile:[self modsListPath] encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSString *key = [@"mod." stringByAppendingString:projectId];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSRange c = [line rangeOfString:@":"];
        if (c.location == NSNotFound) continue;
        NSString *k = [[line substringToIndex:c.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *v = [[line substringFromIndex:c.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([k isEqualToString:key] && [v isEqualToString:@"true"]) return YES;
    }
    return NO;
}

// Same edit as the desktop's set_enabled: every other line kept, this mod's line removed, then added when on.
- (NSString *)setMod:(NSString *)projectId enabled:(BOOL)on {
    if (![HZMarketIndex isValidProjectId:projectId]) return @"That is not a valid mod id.";
    NSString *text = [NSString stringWithContentsOfFile:[self modsListPath] encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSString *key = [@"mod." stringByAppendingString:projectId];
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (!line.length) continue;
        NSRange c = [line rangeOfString:@":"];
        if (c.location != NSNotFound && [[[line substringToIndex:c.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] isEqualToString:key]) continue;
        [lines addObject:line];
    }
    if (on) [lines addObject:[key stringByAppendingString:@":true"]];
    NSString *out = lines.count ? [[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] : @"";
    NSError *err = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:_home withIntermediateDirectories:YES attributes:nil error:nil];
    if (![out writeToFile:[self modsListPath] atomically:YES encoding:NSUTF8StringEncoding error:&err]) return err.localizedDescription;
    return nil;
}

#pragma mark - Placing and removing

- (NSString *)placeDownloaded:(NSString *)temp project:(HZMarketProject *)p version:(HZMarketVersion *)v index:(HZMarketIndex *)index {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *(^fail)(NSString *) = ^NSString *(NSString *why) { [fm removeItemAtPath:temp error:nil]; return why; };

    NSString *refusal = [[self class] refusalFor:p version:v index:index];
    if (refusal) return fail(refusal);

    NSDictionary *a = [fm attributesOfItemAtPath:temp error:nil];
    if (![a.fileType isEqualToString:NSFileTypeRegular]) return fail(@"The download is not a regular file.");
    if (a.fileSize != v.file.size) return fail([NSString stringWithFormat:@"The file is %llu bytes, the registry lists %llu. Nothing was installed.", (unsigned long long)a.fileSize, v.file.size]);
    NSString *hash = [[self class] sha256OfFileAtPath:temp];
    if (![hash isEqualToString:v.file.sha256]) return fail(@"The file's SHA-256 is not the one the registry lists. Nothing was installed.");
    if (![[self class] looksLikeZipAtPath:temp]) return fail(@"The file is not a ZIP container, which every kind here must be. Nothing was installed.");

    NSString *relative = [[self class] relativePathForProject:p version:v];
    NSString *target = [_home stringByAppendingPathComponent:relative];
    // Never replace something the player put there themselves (the desktop refuses the same way).
    NSMutableArray<NSDictionary *> *entries = [self rawEntries];
    NSDictionary *ours = nil;
    for (NSDictionary *e in entries) if ([e[@"source"] isEqual:@"horizon"] && [e[@"project"] isEqual:p.projectId]) { ours = e; break; }
    for (NSDictionary *e in entries) {
        if (e == ours) continue;
        if ([e[@"file"] isEqual:relative]) return fail([NSString stringWithFormat:@"%@ belongs to %@: remove it first.", relative, e[@"title"] ?: @"another install"]);
    }
    BOOL targetExists = [fm fileExistsAtPath:target];
    if (targetExists && ![ours[@"file"] isEqual:relative]) return fail([NSString stringWithFormat:@"%@ is already there and the app did not put it there. Move it away first.", relative]);
    if ([p.kind isEqualToString:@"mod"]) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:[[_home stringByAppendingPathComponent:kModsDir] stringByAppendingPathComponent:p.projectId] isDirectory:&isDir] && isDir)
            return fail([NSString stringWithFormat:@"A mod folder named %@ is already in horizon-mods. Move it away first.", p.projectId]);
    }

    NSError *err = nil;
    [fm createDirectoryAtPath:[target stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&err];
    if (err) return fail(err.localizedDescription);
    // Replace atomically: the old file (our own earlier version) goes only when the new one is in place.
    if (targetExists) {
        NSURL *result = nil;
        if (![fm replaceItemAtURL:[NSURL fileURLWithPath:target] withItemAtURL:[NSURL fileURLWithPath:temp] backupItemName:nil options:0 resultingItemURL:&result error:&err])
            return fail(err.localizedDescription ?: @"Could not replace the old version.");
    } else if (![fm moveItemAtPath:temp toPath:target error:&err]) {
        return fail(err.localizedDescription ?: @"Could not move the file into place.");
    }

    // An older version of ours in another file (a resource pack's name changes with its version) goes now.
    NSString *oldFile = ours[@"file"];
    if ([oldFile isKindOfClass:[NSString class]] && ![oldFile isEqual:relative] && [[self class] fileIsInsideInstallFolders:oldFile])
        [fm removeItemAtPath:[_home stringByAppendingPathComponent:oldFile] error:nil];

    NSDictionary *entry = @{
        @"source": @"horizon", @"project": p.projectId, @"slug": p.projectId, @"title": p.name,
        @"kind": [p.kind isEqualToString:@"mod"] ? @"mod" : p.kind,
        @"version": v.version, @"number": v.version, @"file": relative,
        @"checksum": [@"SHA-256:" stringByAppendingString:v.file.sha256],
        @"page": [@"https://horizon-rust.github.io/horizon-mods/" stringByAppendingString:p.projectId],
        @"dependency": @NO, @"verdict": @"Unsigned",
    };
    NSMutableArray *next = [NSMutableArray array];
    for (NSDictionary *e in entries) if (e != ours) [next addObject:e];
    [next addObject:entry];
    if (![self saveRawEntries:next]) return @"The file is in place but the install record could not be written.";
    // The player asked for it: a mod starts on, as on the desktop. A pack is chosen in the game.
    if ([p.kind isEqualToString:@"mod"]) {
        NSString *e = [self setMod:p.projectId enabled:YES];
        if (e) return [@"Installed, but it could not be turned on: " stringByAppendingString:e];
    }
    return nil;
}

- (NSString *)removeProject:(NSString *)projectId {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSDictionary *> *entries = [self rawEntries];
    NSDictionary *mine = nil;
    for (NSDictionary *e in entries) if ([e[@"source"] isEqual:@"horizon"] && [e[@"project"] isEqual:projectId]) { mine = e; break; }
    if (!mine) return @"That project is not installed by this app.";
    NSString *file = mine[@"file"];
    if (![file isKindOfClass:[NSString class]] || ![[self class] fileIsInsideInstallFolders:file]) return @"The record names a file outside the install folders, so the app will not touch it.";
    NSString *path = [_home stringByAppendingPathComponent:file];
    // A symlink planted at the file's place is removed as a link, never followed.
    NSError *err = nil;
    if ([fm fileExistsAtPath:path] || [fm destinationOfSymbolicLinkAtPath:path error:nil]) {
        if (![fm removeItemAtPath:path error:&err]) return err.localizedDescription;
    }
    NSMutableArray *next = [NSMutableArray array];
    for (NSDictionary *e in entries) if (e != mine) [next addObject:e];
    if (![self saveRawEntries:next]) return @"The file was removed but the record could not be updated.";
    if ([mine[@"kind"] isEqual:@"mod"]) [self setMod:projectId enabled:NO];
    return nil;
}

@end
