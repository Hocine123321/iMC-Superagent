#import "ModrinthClient.h"
#import "MarketIndex.h"

static NSString *const kAPI = @"https://api.modrinth.com/v2";
static NSString *const kCDN = @"https://cdn.modrinth.com/";

@implementation HZModrinthFile
@end
@implementation HZModrinthVersion
@end
@implementation HZModrinthProject
@end

static NSString *Text(id d, NSString *k) {
    id v = [d isKindOfClass:[NSDictionary class]] ? d[k] : nil;
    return [v isKindOfClass:[NSString class]] ? v : nil;
}
static NSArray *List(id d, NSString *k) {
    id v = [d isKindOfClass:[NSDictionary class]] ? d[k] : nil;
    return [v isKindOfClass:[NSArray class]] ? v : nil;
}

@implementation HZModrinthClient

#pragma mark - Rules

+ (NSString *)apiBase { return kAPI; }

+ (BOOL)isHex:(NSString *)s length:(NSUInteger)n {
    if (s.length != n) return NO;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return NO;
    }
    return YES;
}

+ (BOOL)isProjectId:(NSString *)s {
    if (s.length != 8) return NO;
    for (NSUInteger i = 0; i < 8; i++) {
        unichar c = [s characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))) return NO;
    }
    return YES;
}

// launcher/src/browser.rs safe_name: one plain name, at most 200 bytes, not hidden, no trailing dot or space,
// no control characters and none of / \ : * ? " < > |
+ (BOOL)isSafeFileName:(NSString *)name {
    if (!name.length || [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 200) return NO;
    if ([name hasPrefix:@"."] || [name hasSuffix:@"."] || [name hasSuffix:@" "]) return NO;
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    if ([name rangeOfCharacterFromSet:bad].location != NSNotFound) return NO;
    if ([name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return NO;
    return YES;
}

// Modrinth serves files as https://cdn.modrinth.com/data/<project>/versions/<version>/<file name>
// (the name percent-encoded). Anything else is refused, as is a path that climbs.
+ (BOOL)isCDNFileURL:(NSString *)url {
    if (![url hasPrefix:kCDN] || [url rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) return NO;
    if ([url containsString:@"?"] || [url containsString:@"#"] || [url containsString:@".."]) return NO;
    NSArray *parts = [[url substringFromIndex:kCDN.length] componentsSeparatedByString:@"/"];
    if (parts.count != 5 || ![parts[0] isEqual:@"data"] || ![parts[2] isEqual:@"versions"]) return NO;
    for (NSString *p in parts) if (!p.length) return NO;
    return [self isProjectId:parts[1]] && [parts[3] length] >= 6;
}

+ (NSString *)encode:(NSString *)s {
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"];
    return [s stringByAddingPercentEncodingWithAllowedCharacters:ok] ?: @"";
}

+ (NSString *)searchURLForText:(NSString *)text game:(NSString *)game offset:(NSUInteger)offset limit:(NSUInteger)limit {
    // facets is an AND of ORs: the kind, and the Minecraft version.
    NSString *facets = [NSString stringWithFormat:@"[[\"project_type:resourcepack\"],[\"versions:%@\"]]", game];
    NSString *index = text.length ? @"relevance" : @"downloads";
    NSMutableString *u = [NSMutableString stringWithFormat:@"%@/search?facets=%@&index=%@&offset=%lu&limit=%lu", kAPI, [self encode:facets], index, (unsigned long)offset, (unsigned long)MAX(1, MIN(limit, 50))];
    if (text.length) [u appendFormat:@"&query=%@", [self encode:text]];
    return u;
}

+ (NSString *)versionsURLForProject:(NSString *)projectId {
    return [NSString stringWithFormat:@"%@/project/%@/version", kAPI, [self encode:projectId]];
}

+ (NSString *)refusalForFile:(HZModrinthFile *)f {
    if (![self isCDNFileURL:f.url]) return @"The file is not on Modrinth's file server.";
    if (![self isSafeFileName:f.name]) return @"The file name is not a plain name.";
    if (![f.name.pathExtension.lowercaseString isEqualToString:@"zip"]) return @"A resource pack must be a .zip file.";
    if (![self isHex:f.sha512 length:128] && ![self isHex:f.sha1 length:40]) return @"Modrinth lists no checksum for this file, so it cannot be checked.";
    if (f.size == 0 || f.size > [HZMarketIndex maxFileBytes]) return @"The file size is outside what the app accepts (64 MB at most).";
    return nil;
}

#pragma mark - Parsing

+ (NSArray<HZModrinthProject *> *)parseSearch:(NSData *)json total:(NSUInteger *)total error:(NSString **)error {
    if (json.length > (4u << 20)) { if (error) *error = @"Modrinth's answer was larger than the app reads."; return nil; }
    id root = json.length ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    NSArray *hits = List(root, @"hits");
    if (!hits) { if (error) *error = @"Modrinth's answer was not what the app expects."; return nil; }
    NSMutableArray *out = [NSMutableArray array];
    for (id h in hits) {
        if (![h isKindOfClass:[NSDictionary class]]) continue;
        if (![Text(h, @"project_type") isEqual:@"resourcepack"]) continue;
        NSString *pid = Text(h, @"project_id");
        if (![self isProjectId:pid]) continue;
        HZModrinthProject *p = [HZModrinthProject new];
        p.projectId = pid;
        p.slug = Text(h, @"slug") ?: pid;
        p.title = Text(h, @"title") ?: p.slug;
        p.summary = Text(h, @"description") ?: @"";
        p.author = Text(h, @"author") ?: @"";
        p.license = Text(h, @"license") ?: @"";
        NSString *icon = Text(h, @"icon_url");
        p.iconURL = [icon hasPrefix:@"https://cdn.modrinth.com/"] ? icon : nil;   // images only from Modrinth's server
        id dl = h[@"downloads"];
        p.downloads = [dl isKindOfClass:[NSNumber class]] ? [dl unsignedLongLongValue] : 0;
        [out addObject:p];
    }
    id t = [root isKindOfClass:[NSDictionary class]] ? root[@"total_hits"] : nil;
    if (total) *total = [t isKindOfClass:[NSNumber class]] ? [t unsignedIntegerValue] : out.count;
    return out;
}

+ (HZModrinthVersion *)pickVersion:(NSData *)json game:(NSString *)game reason:(NSString **)reason {
    if (json.length > (4u << 20)) { if (reason) *reason = @"Modrinth's answer was larger than the app reads."; return nil; }
    id root = json.length ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    if (![root isKindOfClass:[NSArray class]]) { if (reason) *reason = @"Modrinth's answer was not what the app expects."; return nil; }
    NSMutableArray<NSDictionary *> *versions = [NSMutableArray array];
    for (id v in (NSArray *)root) if ([v isKindOfClass:[NSDictionary class]]) [versions addObject:v];
    // Newest first; ISO dates sort as text.
    [versions sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [(Text(b, @"date_published") ?: @"") compare:(Text(a, @"date_published") ?: @"")];
    }];
    NSString *firstProblem = nil; BOOL anyForGame = NO;
    for (NSDictionary *v in versions) {
        NSString *status = Text(v, @"status");
        if (status && ![status isEqual:@"listed"]) continue;
        if (![List(v, @"game_versions") containsObject:game]) continue;
        anyForGame = YES;
        // The primary file, else the first.
        NSDictionary *pick = nil;
        for (id f in List(v, @"files") ?: @[]) {
            if (![f isKindOfClass:[NSDictionary class]]) continue;
            if (!pick) pick = f;
            if ([f[@"primary"] isEqual:@YES]) { pick = f; break; }
        }
        if (!pick) continue;
        HZModrinthFile *file = [HZModrinthFile new];
        file.name = Text(pick, @"filename") ?: @"";
        file.url = Text(pick, @"url") ?: @"";
        id sz = pick[@"size"];
        file.size = [sz isKindOfClass:[NSNumber class]] ? [sz unsignedLongLongValue] : 0;
        NSDictionary *hashes = [pick[@"hashes"] isKindOfClass:[NSDictionary class]] ? pick[@"hashes"] : @{};
        file.sha512 = Text(hashes, @"sha512").lowercaseString;
        file.sha1 = Text(hashes, @"sha1").lowercaseString;
        NSString *why = [self refusalForFile:file];
        if (why) { if (!firstProblem) firstProblem = why; continue; }
        HZModrinthVersion *ver = [HZModrinthVersion new];
        ver.versionId = Text(v, @"id") ?: @"";
        // The page and the install record both show this; an empty one falls back to the id so they always agree.
        NSString *number = Text(v, @"version_number");
        ver.number = number.length ? number : (Text(v, @"id") ?: @"");
        ver.published = Text(v, @"date_published") ?: @"";
        ver.gameVersions = List(v, @"game_versions") ?: @[];
        ver.file = file;
        return ver;
    }
    if (reason) *reason = !anyForGame ? [NSString stringWithFormat:@"No version of this pack is made for Minecraft %@.", game] : (firstProblem ?: @"This pack has no file the app can install.");
    return nil;
}

#pragma mark - Network

- (void)get:(NSString *)url completion:(void (^)(NSData *data, NSString *error))done {
    NSURL *u = [NSURL URLWithString:url];
    if (!u || ![url hasPrefix:kAPI]) { done(nil, @"That is not Modrinth's address."); return; }
    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.timeoutIntervalForRequest = 30; cfg.timeoutIntervalForResource = 60;
    NSURLSession *s = [NSURLSession sessionWithConfiguration:cfg];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u];
    // Modrinth asks for a user agent that names the project.
    [req setValue:@"Hocine123321/iMC-Superagent iMC-Horizon-iOS" forHTTPHeaderField:@"User-Agent"];
    [[s dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSInteger code = [r isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)r).statusCode : 0;
        NSString *err = nil;
        if (e) err = [NSString stringWithFormat:@"No connection to Modrinth: %@", e.localizedDescription];
        else if (code == 429) err = @"Modrinth asks to slow down: try again in a minute.";
        else if (code != 200) err = [NSString stringWithFormat:@"Modrinth answered %ld.", (long)code];
        dispatch_async(dispatch_get_main_queue(), ^{ done(err ? nil : d, err); });
        [s finishTasksAndInvalidate];
    }] resume];
}

- (void)searchText:(NSString *)text offset:(NSUInteger)offset completion:(void (^)(NSArray<HZModrinthProject *> *_Nullable, NSUInteger, NSString *_Nullable))done {
    [self get:[HZModrinthClient searchURLForText:text game:@"26.3" offset:offset limit:30] completion:^(NSData *d, NSString *err) {
        if (!d) { done(nil, 0, err); return; }
        NSString *perr = nil; NSUInteger total = 0;
        NSArray *p = [HZModrinthClient parseSearch:d total:&total error:&perr];
        done(p, total, p ? nil : perr);
    }];
}

- (void)bodyOfProject:(HZModrinthProject *)project completion:(void (^)(NSString *_Nullable, NSString *_Nullable))done {
    if (![HZModrinthClient isProjectId:project.projectId]) { done(nil, @"That is not a Modrinth project id."); return; }
    [self get:[NSString stringWithFormat:@"%@/project/%@", kAPI, project.projectId] completion:^(NSData *d, NSString *err) {
        if (!d) { done(nil, err); return; }
        id root = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        NSString *body = [root isKindOfClass:[NSDictionary class]] && [root[@"body"] isKindOfClass:[NSString class]] ? root[@"body"] : nil;
        if (!body) { done(nil, @"Modrinth sent no description for this project."); return; }
        done(body.length > 60000 ? [body substringToIndex:60000] : body, nil);
    }];
}

- (void)newestVersionOf:(HZModrinthProject *)project completion:(void (^)(HZModrinthVersion *_Nullable, NSString *_Nullable))done {
    [self get:[HZModrinthClient versionsURLForProject:project.projectId] completion:^(NSData *d, NSString *err) {
        if (!d) { done(nil, err); return; }
        NSString *why = nil;
        HZModrinthVersion *v = [HZModrinthClient pickVersion:d game:@"26.3" reason:&why];
        done(v, v ? nil : why);
    }];
}
@end
