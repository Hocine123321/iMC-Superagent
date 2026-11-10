#import "DownloadPlan.h"

@implementation HZDownloadFile
@end

// Hosts Mojang serves the game from. Checked against the 26.3 version JSON: the libraries are on
// libraries.minecraft.net, the client jar and logging file on piston-data.mojang.com, the asset
// index on piston-meta.mojang.com and the asset objects on resources.download.minecraft.net.
static NSString *const kObjects = @"https://resources.download.minecraft.net";

static BOOL IsHex40(NSString *s) {
    if (s.length != 40) return NO;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return NO;
    }
    return YES;
}

static NSString *Str(id d, NSString *key) {
    if (![d isKindOfClass:NSDictionary.class]) return nil;
    id v = d[key];
    return [v isKindOfClass:NSString.class] && [v length] > 0 ? v : nil;
}

static unsigned long long ListedSize(id d) {
    if (![d isKindOfClass:NSDictionary.class]) return 0;
    id v = d[@"size"];
    if (![v isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID()) return 0;
    return [v longLongValue] > 0 ? [v unsignedLongLongValue] : 0;
}

// Mirrors horizon-prepare artifacts.rs: an iPhone is "linux" on arm64.
static NSString *const kSystem = @"linux";

// A rule list, as the official launcher reads it: the last rule that matches decides, no rules
// means allowed. A rule that asks about architecture, version or features is not guessed at.
static BOOL LibraryAllowed(NSDictionary *library, NSString **unsupported) {
    id rules = library[@"rules"];
    if (![rules isKindOfClass:NSArray.class] || [rules count] == 0) return YES;
    BOOL allowed = NO;
    for (id rule in rules) {
        if (![rule isKindOfClass:NSDictionary.class]) { *unsupported = @"a rule that is not an object"; return NO; }
        id os = rule[@"os"];
        if (os && ![os isKindOfClass:NSDictionary.class]) { *unsupported = @"a rule with an unreadable os"; return NO; }
        if ([os[@"arch"] isKindOfClass:NSString.class] || [os[@"version"] isKindOfClass:NSString.class]) {
            *unsupported = @"a rule about architecture or version"; return NO;
        }
        id features = rule[@"features"];
        if (features && ![features isEqual:NSNull.null] && !([features isKindOfClass:NSDictionary.class] && [features count] == 0)) {
            *unsupported = @"a rule about features"; return NO;
        }
        NSString *name = [os isKindOfClass:NSDictionary.class] ? Str(os, @"name") : nil;
        if (name && ![name isEqualToString:kSystem]) continue;
        allowed = [Str(rule, @"action") isEqualToString:@"allow"];
    }
    return allowed;
}

// "natives-linux-arm64" ends with "arm64" after a dash; "arm64" alone matches too.
static BOOL ClassifierEndsWith(NSString *classifier, NSArray<NSString *> *names) {
    for (NSString *n in names) {
        if ([classifier isEqualToString:n]) return YES;
        if ([classifier hasSuffix:[@"-" stringByAppendingString:n]]) return YES;
    }
    return NO;
}

// Modern manifests list x64 and ARM natives with OS-only rules; keep the arm64 ones (this is a
// phone). A plain natives-<os> jar is the x64 build when the manifest also lists an arm variant of
// it, so it is dropped then. (Same as artifacts.rs native_library_matches with arm64.)
static BOOL NativeMatches(NSDictionary *library, NSSet<NSString *> *names) {
    NSString *name = Str(library, @"name") ?: @"";
    NSArray *parts = [name componentsSeparatedByString:@":"];
    NSString *classifier = parts.count > 3 ? parts[3] : @"";
    if (ClassifierEndsWith(classifier, @[@"arm64", @"aarch64", @"aarch_64"])) return YES;
    if (ClassifierEndsWith(classifier, @[@"x86_64", @"x64"])) return NO;
    if ([classifier hasPrefix:@"natives-"]) {
        for (NSString *suffix in @[@"arm64", @"aarch64"]) {
            if ([names containsObject:[NSString stringWithFormat:@"%@-%@", name, suffix]]) return NO;
        }
    }
    return YES;
}

@implementation HZDownloadPlan

+ (BOOL)isMojangHost:(NSString *)host {
    static NSSet *hosts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hosts = [NSSet setWithArray:@[@"libraries.minecraft.net", @"piston-data.mojang.com",
                                      @"piston-meta.mojang.com", @"resources.download.minecraft.net"]];
    });
    return [hosts containsObject:host.lowercaseString];
}

+ (NSString *)safeRelativePath:(NSString *)path {
    if (path.length == 0 || [path containsString:@"\\"] || [path hasPrefix:@"/"]) return nil;
    for (NSString *part in [path componentsSeparatedByString:@"/"]) {
        if (part.length == 0 || [part isEqualToString:@"."] || [part isEqualToString:@".."]) return nil;
    }
    return path;
}

// One file, or nil with `error` set. `path` is relative to the game folder.
+ (HZDownloadFile *)fileFrom:(id)entry path:(NSString *)path error:(NSString **)error {
    NSString *url = Str(entry, @"url"), *sha1 = Str(entry, @"sha1");
    NSURL *u = url ? [NSURL URLWithString:url] : nil;
    if (!u || ![u.scheme isEqualToString:@"https"] || ![self isMojangHost:u.host ?: @""]) {
        *error = [NSString stringWithFormat:@"%@ is not on a Mojang server.", path]; return nil;
    }
    if (!sha1 || !IsHex40(sha1)) { *error = [NSString stringWithFormat:@"%@ has no usable sha1.", path]; return nil; }
    NSString *safe = [self safeRelativePath:path];
    if (!safe) { *error = [NSString stringWithFormat:@"Unsafe path %@ in the version file.", path]; return nil; }
    HZDownloadFile *f = [HZDownloadFile new];
    f.url = url; f.sha1 = sha1; f.size = ListedSize(entry); f.path = safe;
    return f;
}

+ (HZDownloadPlan *)planGameFromVersionJSON:(NSData *)json version:(NSString *)version {
    HZDownloadPlan *plan = [HZDownloadPlan new];
    plan.game = @[]; plan.assets = @[];
    NSString *error = nil;
    id root = json.length ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    if (![root isKindOfClass:NSDictionary.class]) { plan.error = @"The version file is not readable."; return plan; }
    NSString *safeVersion = [self safeRelativePath:version];
    if (!safeVersion || [safeVersion containsString:@"/"]) { plan.error = @"The version name is not usable."; return plan; }

    NSMutableArray<HZDownloadFile *> *game = [NSMutableArray new];
    HZDownloadFile *client = [self fileFrom:root[@"downloads"][@"client"]
                                       path:[NSString stringWithFormat:@"versions/%@/%@.jar", safeVersion, safeVersion] error:&error];
    if (!client) { plan.error = error ?: @"The version file has no client download."; return plan; }
    [game addObject:client];

    NSArray *libraries = root[@"libraries"];
    if (![libraries isKindOfClass:NSArray.class]) { plan.error = @"The version file has no libraries."; return plan; }
    NSMutableSet<NSString *> *names = [NSMutableSet new];
    for (id l in libraries) if (Str(l, @"name")) [names addObject:Str(l, @"name")];
    NSUInteger count = 0;
    for (id library in libraries) {
        if (![library isKindOfClass:NSDictionary.class]) continue;
        NSString *why = nil;
        BOOL ok = LibraryAllowed(library, &why);
        if (why) { plan.error = [NSString stringWithFormat:@"Library %@ has %@, which this app does not guess at.", Str(library, @"name") ?: @"?", why]; return plan; }
        // A pre-1.19 library keeps its natives in a classifier map. 26.3 has none; refuse rather than skip.
        if ([library[@"natives"] isKindOfClass:NSDictionary.class]) {
            plan.error = [NSString stringWithFormat:@"Library %@ uses old-style natives, which this app does not handle.", Str(library, @"name") ?: @"?"]; return plan;
        }
        id artifact = library[@"downloads"][@"artifact"];
        if (!ok || ![artifact isKindOfClass:NSDictionary.class] || !NativeMatches(library, names)) continue;
        HZDownloadFile *f = [self fileFrom:artifact path:[@"libraries/" stringByAppendingString:Str(artifact, @"path") ?: @""] error:&error];
        if (!f) { plan.error = error; return plan; }
        [game addObject:f]; count++;
    }
    id logging = root[@"logging"][@"client"][@"file"];
    if ([logging isKindOfClass:NSDictionary.class]) {
        HZDownloadFile *f = [self fileFrom:logging path:[@"assets/log_configs/" stringByAppendingString:Str(logging, @"id") ?: @""] error:&error];
        if (!f) { plan.error = error; return plan; }
        [game addObject:f];
    }
    id index = root[@"assetIndex"];
    HZDownloadFile *indexFile = [self fileFrom:index path:[NSString stringWithFormat:@"assets/indexes/%@.json", Str(index, @"id") ?: @""] error:&error];
    if (!indexFile) { plan.error = error; return plan; }
    [game addObject:indexFile];
    plan.game = game; plan.libraryCount = count;
    return plan;
}

- (BOOL)addAssetsFromIndexJSON:(NSData *)json error:(NSString **)error {
    id root = json.length ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    id objects = [root isKindOfClass:NSDictionary.class] ? root[@"objects"] : nil;
    if (![objects isKindOfClass:NSDictionary.class]) { if (error) *error = @"The asset index has no objects."; return NO; }
    NSMutableDictionary<NSString *, NSNumber *> *bySha = [NSMutableDictionary new];
    for (id key in objects) {
        id o = objects[key];
        NSString *hash = Str(o, @"hash");
        if (!hash) continue;
        if (!IsHex40(hash)) { if (error) *error = [NSString stringWithFormat:@"Bad asset hash %@ in the asset index.", hash]; return NO; }
        bySha[hash] = @(ListedSize(o));
    }
    NSMutableArray<HZDownloadFile *> *out = [NSMutableArray new];
    for (NSString *hash in [bySha.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        HZDownloadFile *f = [HZDownloadFile new];
        NSString *path = [NSString stringWithFormat:@"%@/%@", [hash substringToIndex:2], hash];
        f.url = [NSString stringWithFormat:@"%@/%@", kObjects, path];
        f.sha1 = hash; f.size = bySha[hash].unsignedLongLongValue;
        f.path = [@"assets/objects/" stringByAppendingString:path];
        [out addObject:f];
    }
    self.assets = out;
    return YES;
}

- (NSUInteger)fileCount { return self.game.count + self.assets.count; }
- (unsigned long long)totalBytes {
    unsigned long long n = 0;
    for (HZDownloadFile *f in self.game) n += f.size;
    for (HZDownloadFile *f in self.assets) n += f.size;
    return n;
}
@end
