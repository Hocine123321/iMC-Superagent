#import "MarketIndex.h"

static NSString *const kFileHost = @"https://github.com/horizon-rust/horizon-mods/releases/download/";
static NSString *const kImageHost = @"https://horizon-rust.github.io/horizon-mods/";
static const NSUInteger kMaxScreenshots = 8;
static const NSUInteger kSchema = 1;

@implementation HZMarketFile
@end
@implementation HZMarketVersion
@end
@implementation HZMarketProject
@end
@implementation HZMarketRevoked
@end

// JSON accessors that never throw: a wrong type reads as absent.
static NSString *JText(id d, NSString *k) {
    id v = [d isKindOfClass:NSDictionary.class] ? d[k] : nil;
    return [v isKindOfClass:NSString.class] ? v : nil;
}
static NSArray *JList(id d, NSString *k) {
    id v = [d isKindOfClass:NSDictionary.class] ? d[k] : nil;
    return [v isKindOfClass:NSArray.class] ? v : nil;
}
// A whole non-negative number, or -1 when absent or not one (a bool or a fraction is not a count).
static long long JCount(id d, NSString *k) {
    id v = [d isKindOfClass:NSDictionary.class] ? d[k] : nil;
    if (![v isKindOfClass:NSNumber.class]) return -1;
    if (CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID()) return -1;
    double dv = [v doubleValue];
    if (dv < 0 || dv != (double)(long long)dv) return -1;
    return [v longLongValue];
}
static BOOL NoWhitespace(NSString *s) {
    return [s rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location == NSNotFound;
}

@implementation HZMarketIndex

+ (unsigned long long)maxFileBytes { return 64ull << 20; }
+ (unsigned long long)maxIndexBytes { return 16ull << 20; }

+ (BOOL)isValidProjectId:(NSString *)s {
    if (s.length < 1 || s.length > 64) return NO;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_')) return NO;
    }
    return YES;
}

+ (BOOL)isPlainFileName:(NSString *)s {
    if (s.length < 1 || s.length > 128 || [s hasPrefix:@"."]) return NO;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        BOOL ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-' || c == '+';
        if (!ok) return NO;
    }
    return YES;
}

+ (BOOL)isLowerHex64:(NSString *)s {
    if (s.length != 64) return NO;
    for (NSUInteger i = 0; i < 64; i++) {
        unichar c = [s characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return NO;
    }
    return YES;
}

// A release asset of the registry: <host><tag>/<name>, each part plain, nothing else after it.
+ (BOOL)isRegistryFileURL:(NSString *)url {
    if (![url hasPrefix:kFileHost] || !NoWhitespace(url)) return NO;
    NSArray *parts = [[url substringFromIndex:kFileHost.length] componentsSeparatedByString:@"/"];
    if (parts.count != 2) return NO;
    for (NSString *p in parts) {
        if (p.length == 0 || [p isEqualToString:@"."] || [p isEqualToString:@".."]) return NO;
        for (NSUInteger i = 0; i < p.length; i++) {
            unichar c = [p characterAtIndex:i];
            BOOL ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-' || c == '+' || c == '%';
            if (!ok) return NO;
        }
    }
    return YES;
}

+ (BOOL)isRegistryImageURL:(NSString *)url {
    if (![url hasPrefix:kImageHost] || !NoWhitespace(url) || url.length == kImageHost.length) return NO;
    NSString *rest = [url substringFromIndex:kImageHost.length];
    if ([rest containsString:@".."] || [rest containsString:@"\\"] || [rest containsString:@"?"] || [rest containsString:@"#"]) return NO;
    NSString *ext = rest.pathExtension.lowercaseString;
    return [ext isEqualToString:@"png"] || [ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"];
}

+ (NSString *)extensionForKind:(NSString *)kind {
    if ([kind isEqualToString:@"mod"]) return @"hmod";
    if ([kind isEqualToString:@"native-mod"]) return @"hnmod";
    if ([kind isEqualToString:@"modpack"]) return @"hpack";
    if ([kind isEqualToString:@"shader"]) return @"hshader";
    if ([kind isEqualToString:@"resourcepack"] || [kind isEqualToString:@"shaderpack"] || [kind isEqualToString:@"datapack"]) return @"zip";
    return nil;
}

+ (HZMarketSupport)supportForKind:(NSString *)kind {
    if ([kind isEqualToString:@"mod"] || [kind isEqualToString:@"resourcepack"] || [kind isEqualToString:@"shader"]) return HZMarketInstallable;
    if ([kind isEqualToString:@"native-mod"]) return HZMarketNeedsDesktop;
    return HZMarketNotYet;
}

// Parsing one project; returns nil with `bad` set on a rule violation.
+ (HZMarketProject *)projectFrom:(id)d bad:(NSString **)bad {
    NSString *pid = JText(d, @"id");
    if (!pid || ![self isValidProjectId:pid]) { *bad = [NSString stringWithFormat:@"project id %@ is not [a-z0-9_]{1,64}", pid ?: @"(missing)"]; return nil; }
    #define FAIL(...) do { *bad = [NSString stringWithFormat:@"%@: %@", pid, [NSString stringWithFormat:__VA_ARGS__]]; return nil; } while (0)
    NSString *kind = JText(d, @"kind"), *name = JText(d, @"name"), *license = JText(d, @"license"), *source = JText(d, @"source");
    if (!kind.length) FAIL(@"no kind");
    if (![name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length ||
        ![license stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) FAIL(@"needs a name and a licence");
    if (![source hasPrefix:@"https://"] || source.length == 8 || !NoWhitespace(source)) FAIL(@"source is not an https:// address");

    HZMarketProject *p = [HZMarketProject new];
    p.projectId = pid; p.kind = kind; p.name = name; p.license = license; p.source = source;
    p.summary = JText(d, @"summary") ?: @"";
    p.details = JText(d, @"description") ?: @"";
    NSMutableArray *authors = [NSMutableArray new];
    for (id a in JList(d, @"authors") ?: @[]) if ([a isKindOfClass:NSString.class]) [authors addObject:a];
    p.authors = authors;
    NSMutableArray *cats = [NSMutableArray new];
    for (id c in JList(d, @"categories") ?: @[]) if ([c isKindOfClass:NSString.class]) [cats addObject:c];
    p.categories = cats;

    // Images are not required for a project to be listed, so a bad address drops the image instead
    // of the project (the desktop likewise only needs them to be https; here they must also be the
    // registry's own site, since the phone loads them without asking).
    NSString *icon = JText(d, @"icon");
    if (icon) {
        if (![icon hasPrefix:@"https://"] || !NoWhitespace(icon)) FAIL(@"icon is not an https:// address");
        p.icon = [self isRegistryImageURL:icon] ? icon : nil;
    }
    NSArray *shots = JList(d, @"screenshots") ?: @[];
    if (shots.count > kMaxScreenshots) FAIL(@"%lu screenshots, at most %lu", (unsigned long)shots.count, (unsigned long)kMaxScreenshots);
    NSMutableArray *okShots = [NSMutableArray new];
    for (id s in shots) {
        if (![s isKindOfClass:NSString.class] || ![s hasPrefix:@"https://"] || !NoWhitespace(s)) FAIL(@"a screenshot is not an https:// address");
        if ([self isRegistryImageURL:s]) [okShots addObject:s];
    }
    p.screenshots = okShots;
    NSString *key = JText(d, @"key");
    p.key = key.length ? key : nil;
    long long dl = JCount(d, @"downloads"), st = JCount(d, @"stars");
    p.downloads = dl > 0 ? (unsigned long long)dl : 0;
    p.stars = st > 0 ? (unsigned long long)st : 0;
    p.support = [self supportForKind:kind];

    NSArray *versions = JList(d, @"versions");
    if (!versions.count) FAIL(@"has no version");
    NSString *ext = [self extensionForKind:kind];
    NSMutableArray<HZMarketVersion *> *out = [NSMutableArray new];
    NSMutableSet *seen = [NSMutableSet new];
    for (id vd in versions) {
        NSString *vs = JText(vd, @"version");
        if (!vs.length || ![vs stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length || [seen containsObject:vs]) FAIL(@"empty or repeated version");
        [seen addObject:vs];
        #define VFAIL(...) do { *bad = [NSString stringWithFormat:@"%@ %@: %@", pid, vs, [NSString stringWithFormat:__VA_ARGS__]]; return nil; } while (0)
        id fd = [vd isKindOfClass:NSDictionary.class] ? vd[@"file"] : nil;
        NSString *fname = JText(fd, @"name"), *furl = JText(fd, @"url"), *fsha = JText(fd, @"sha256"), *fsig = JText(fd, @"signature");
        long long fsize = JCount(fd, @"size");
        if (!fname || ![self isPlainFileName:fname] || (ext && ![fname hasSuffix:[@"." stringByAppendingString:ext]])) VFAIL(@"%@ is not a plain file name for a %@", fname ?: @"(missing)", kind);
        // https for every kind (the desktop's rule); the registry's release host for the kinds the
        // phone can install (the phone's own, stricter rule). A native mod is only listed.
        if (!furl || ![furl hasPrefix:@"https://"] || !NoWhitespace(furl)) VFAIL(@"the file address is not https://");
        if (p.support == HZMarketInstallable && ![self isRegistryFileURL:furl]) VFAIL(@"the file is not on the registry's release host");
        if (!fsha || ![self isLowerHex64:fsha]) VFAIL(@"not a lowercase hex SHA-256");
        if (fsize <= 0 || (unsigned long long)fsize > [self maxFileBytes]) VFAIL(@"size is not 1 byte to 64 MiB");
        if (p.key && !fsig) VFAIL(@"unsigned, but the project has a key");
        if (!p.key && fsig) VFAIL(@"signed, but the project has no key");
        HZMarketFile *f = [HZMarketFile new];
        f.name = fname; f.url = furl; f.size = (unsigned long long)fsize; f.sha256 = fsha; f.signature = fsig;
        HZMarketVersion *v = [HZMarketVersion new];
        v.version = vs; v.file = f;
        v.game = JText(vd, @"game") ?: @"";
        v.published = JText(vd, @"published") ?: @"";
        v.changelog = JText(vd, @"changelog") ?: @"";
        [out addObject:v];
        #undef VFAIL
    }
    #undef FAIL
    p.versions = out;
    return p;
}

+ (HZMarketIndex *)parse:(NSData *)json error:(NSString **)error {
    #define REFUSE(msg) do { if (error) *error = (msg); return nil; } while (0)
    if (json.length == 0) REFUSE(@"The registry sent nothing.");
    if (json.length > [self maxIndexBytes]) REFUSE(@"The registry's list is bigger than the app will read.");
    id root = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    if (![root isKindOfClass:NSDictionary.class]) REFUSE(@"That is not a mod index.");
    long long schema = JCount(root, @"schema");
    if (schema < 0) REFUSE(@"That is not a mod index.");
    if ((unsigned long long)schema > kSchema) REFUSE(@"The registry uses a newer format than this app reads. Update the app.");
    NSArray *projects = JList(root, @"projects");
    if (!projects) REFUSE(@"That is not a mod index.");

    NSMutableArray<HZMarketProject *> *out = [NSMutableArray new];
    NSMutableSet *ids = [NSMutableSet new];
    for (id pd in projects) {
        NSString *bad = nil;
        HZMarketProject *p = [self projectFrom:pd bad:&bad];
        if (!p) REFUSE(([NSString stringWithFormat:@"The registry's list failed a check (%@).", bad]));
        if ([ids containsObject:p.projectId]) REFUSE(([NSString stringWithFormat:@"The registry's list failed a check (%@ is listed twice).", p.projectId]));
        [ids addObject:p.projectId];
        [out addObject:p];
    }
    NSMutableArray<HZMarketRevoked *> *rev = [NSMutableArray new];
    for (id rd in JList(root, @"revoked") ?: @[]) {
        NSString *rid = JText(rd, @"id"), *sha = JText(rd, @"sha256");
        if (!rid.length) continue;
        if (sha && ![self isLowerHex64:sha]) REFUSE(([NSString stringWithFormat:@"The registry's list failed a check (revoked %@ has a bad SHA-256).", rid]));
        HZMarketRevoked *r = [HZMarketRevoked new];
        r.projectId = rid; r.sha256 = sha; r.reason = JText(rd, @"reason") ?: @""; r.date = JText(rd, @"date") ?: @"";
        [rev addObject:r];
    }
    HZMarketIndex *index = [HZMarketIndex new];
    index.generated = JText(root, @"generated") ?: @"";
    index.projects = out;
    index.revoked = rev;
    return index;
    #undef REFUSE
}

- (HZMarketProject *)projectWithId:(NSString *)projectId {
    for (HZMarketProject *p in self.projects) if ([p.projectId isEqualToString:projectId]) return p;
    return nil;
}

- (HZMarketRevoked *)revocationFor:(NSString *)projectId sha256:(NSString *)sha256 {
    for (HZMarketRevoked *r in self.revoked) {
        if (![r.projectId isEqualToString:projectId]) continue;
        if (!r.sha256) return r;                                        // every version of the project
        if (sha256 && [r.sha256 caseInsensitiveCompare:sha256] == NSOrderedSame) return r;
    }
    return nil;
}

- (HZMarketVersion *)installableVersionOf:(HZMarketProject *)project game:(NSString *)game {
    for (HZMarketVersion *v in project.versions) {
        if ([v.game isEqualToString:game] && ![self revocationFor:project.projectId sha256:v.file.sha256]) return v;
    }
    return nil;
}

@end
