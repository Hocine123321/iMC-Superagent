#import "Downloader.h"
#import "DownloadPlan.h"
#import "DownloadStore.h"

static NSString *const kManifestURL = @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";
static const NSUInteger kMaxAttempts = 4;

@implementation HZDownloadProgress
@end

@interface HZDownloader ()
@property (copy) NSString *version;
@property (strong) HZDownloadStore *store;
@property (strong) NSURLSession *session;
@property (atomic) BOOL cancelled;
@property (atomic, readwrite) BOOL running;
// Accessed under `lock` only.
@property (strong) NSLock *lock;
@property (strong) HZDownloadProgress *state;
@property (strong) NSDate *lastReport;
@property (copy) void (^report)(HZDownloadProgress *);
@end

@implementation HZDownloader

+ (NSUInteger)concurrency { return 6; }
+ (NSTimeInterval)backoffForAttempt:(NSUInteger)n {
    NSUInteger shift = n > 0 ? n - 1 : 0;
    if (shift > 3) shift = 3;
    return 2.0 * (NSTimeInterval)(1u << shift);   // 2, 4, 8, 16
}
+ (BOOL)shouldRetryStatus:(NSInteger)status {
    return status == 408 || status == 425 || status == 429 || (status >= 500 && status <= 599);
}

+ (NSDictionary<NSString *, NSString *> *)versionEntryIn:(NSData *)manifest version:(NSString *)version {
    id root = manifest.length ? [NSJSONSerialization JSONObjectWithData:manifest options:0 error:nil] : nil;
    NSArray *versions = [root isKindOfClass:NSDictionary.class] ? root[@"versions"] : nil;
    if (![versions isKindOfClass:NSArray.class]) return nil;
    for (id v in versions) {
        if (![v isKindOfClass:NSDictionary.class] || ![v[@"id"] isEqual:version]) continue;
        NSString *url = v[@"url"], *sha1 = v[@"sha1"];
        NSURL *u = [url isKindOfClass:NSString.class] ? [NSURL URLWithString:url] : nil;
        if (!u || ![u.scheme isEqualToString:@"https"] || ![HZDownloadPlan isMojangHost:u.host ?: @""]) return nil;
        if (![sha1 isKindOfClass:NSString.class] || ![HZDownloadStore isHex:sha1 length:40]) return nil;
        return @{ @"url": url, @"sha1": sha1 };
    }
    return nil;
}

- (instancetype)initWithRoot:(NSString *)root version:(NSString *)version {
    if ((self = [super init])) {
        _version = [version copy];
        _store = [[HZDownloadStore alloc] initWithRoot:root];
        _includeServerJar = YES;
        _lock = [NSLock new];
        NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        cfg.timeoutIntervalForRequest = 30;
        cfg.timeoutIntervalForResource = 60 * 30;   // one file, not the whole set
        cfg.HTTPMaximumConnectionsPerHost = [HZDownloader concurrency];
        cfg.HTTPCookieStorage = nil;
        cfg.URLCredentialStorage = nil;
        cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

#pragma mark - progress

- (void)publish:(BOOL)force {
    [self.lock lock];
    NSDate *now = [NSDate date];
    BOOL due = force || !self.lastReport || [now timeIntervalSinceDate:self.lastReport] >= 0.25;
    HZDownloadProgress *copy = nil;
    if (due) {
        self.lastReport = now;
        copy = [HZDownloadProgress new];
        HZDownloadProgress *s = self.state;
        copy.phase = s.phase; copy.filesDone = s.filesDone; copy.filesTotal = s.filesTotal;
        copy.bytesDone = s.bytesDone; copy.bytesTotal = s.bytesTotal; copy.message = s.message; copy.error = s.error;
    }
    void (^cb)(HZDownloadProgress *) = self.report;
    [self.lock unlock];
    if (copy && cb) dispatch_async(dispatch_get_main_queue(), ^{ cb(copy); });
}

- (void)update:(void (^)(HZDownloadProgress *s))change force:(BOOL)force {
    [self.lock lock]; change(self.state); [self.lock unlock];
    [self publish:force];
}

- (void)fail:(NSString *)why {
    self.running = NO;
    [self update:^(HZDownloadProgress *s) { s.phase = HZPhaseFailed; s.error = why; s.message = why; } force:YES];
}

#pragma mark - one request, waited for

// Small JSON files (manifest, version file, asset index). Always off the main thread.
- (NSData *)fetchData:(NSString *)url error:(NSString **)error {
    NSURL *u = [NSURL URLWithString:url];
    if (!u || ![u.scheme isEqualToString:@"https"] || ![HZDownloadPlan isMojangHost:u.host ?: @""]) {
        *error = @"A download address is not on a Mojang server."; return nil;
    }
    for (NSUInteger attempt = 1; attempt <= kMaxAttempts && !self.cancelled; attempt++) {
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block NSData *body = nil; __block NSInteger status = 0; __block NSError *err = nil;
        [[self.session dataTaskWithURL:u completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            body = d; err = e; status = [r isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)r).statusCode : 0;
            dispatch_semaphore_signal(done);
        }] resume];
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        if (!err && status == 200 && body.length) return body;
        BOOL retry = err ? YES : [HZDownloader shouldRetryStatus:status];
        if (!retry || attempt == kMaxAttempts) {
            *error = err ? [NSString stringWithFormat:@"No connection to Mojang (%@).", err.localizedDescription]
                         : [NSString stringWithFormat:@"Mojang answered %ld for a file.", (long)status];
            return nil;
        }
        [NSThread sleepForTimeInterval:[HZDownloader backoffForAttempt:attempt]];
    }
    if (self.cancelled) *error = @"Stopped.";
    return nil;
}

// A JSON file whose sha1 Mojang lists: refuse it if it does not match.
- (NSData *)fetchChecked:(NSString *)url sha1:(NSString *)sha1 what:(NSString *)what error:(NSString **)error {
    NSData *d = [self fetchData:url error:error];
    if (!d) return nil;
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [d writeToFile:tmp atomically:NO];
    NSString *have = [HZDownloadStore sha1OfFileAtPath:tmp];
    [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
    if (!have || ![have isEqualToString:sha1]) { *error = [NSString stringWithFormat:@"The %@ does not match its checksum.", what]; return nil; }
    return d;
}

#pragma mark - one file

// Fetches one file into place. Returns nil on success or the reason. Retries network trouble.
- (NSString *)fetchFile:(HZDownloadFile *)f {
    NSString *dest = [self.store absolutePathFor:f.path];
    if (!dest) return @"A file's path would leave the game folder.";
    NSURL *u = [NSURL URLWithString:f.url];
    NSString *last = @"unknown error";
    for (NSUInteger attempt = 1; attempt <= kMaxAttempts && !self.cancelled; attempt++) {
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block NSString *tmpPath = nil; __block NSInteger status = 0; __block NSError *err = nil;
        NSURLSessionDownloadTask *t = [self.session downloadTaskWithURL:u completionHandler:^(NSURL *loc, NSURLResponse *r, NSError *e) {
            err = e; status = [r isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)r).statusCode : 0;
            if (loc && !e) {
                // The system deletes `loc` when this block returns: move it now, beside the
                // destination (same volume, so the final move is a rename) and named .part.
                NSString *dir = [dest stringByDeletingLastPathComponent];
                [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
                NSString *part = [dest stringByAppendingString:@".part"];
                [[NSFileManager defaultManager] removeItemAtPath:part error:nil];
                if ([[NSFileManager defaultManager] moveItemAtURL:loc toURL:[NSURL fileURLWithPath:part] error:nil]) tmpPath = part;
            }
            dispatch_semaphore_signal(done);
        }];
        [t resume];
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        if (self.cancelled) { if (tmpPath) [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil]; return @"Stopped."; }
        if (tmpPath && status == 200) {
            NSString *bad = [self.store installDownloaded:tmpPath toPath:f.path size:f.size sha1:f.sha1];
            if (!bad) return nil;
            last = bad;                 // a wrong size or hash: fetch it again, it may have been cut short
        } else {
            if (tmpPath) [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
            if (!err && ![HZDownloader shouldRetryStatus:status]) return [NSString stringWithFormat:@"Mojang answered %ld for %@.", (long)status, f.path.lastPathComponent];
            last = err ? err.localizedDescription : [NSString stringWithFormat:@"status %ld", (long)status];
        }
        if (attempt < kMaxAttempts) [NSThread sleepForTimeInterval:[HZDownloader backoffForAttempt:attempt]];
    }
    return self.cancelled ? @"Stopped." : [NSString stringWithFormat:@"%@: %@", f.path.lastPathComponent, last];
}

#pragma mark - the run

- (void)cancel { self.cancelled = YES; }

- (void)startWithProgress:(void (^)(HZDownloadProgress *))progress {
    if (self.running) return;
    self.running = YES;
    self.cancelled = NO;
    self.report = progress;
    self.state = [HZDownloadProgress new];
    self.state.message = @"Starting...";
    self.lastReport = nil;
    [self publish:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [self run]; });
}

- (void)run {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:self.store.root withIntermediateDirectories:YES attributes:nil error:nil];
    // Anything left from a stopped run is unproven: drop it.
    [self.store removePartialFiles];

    // 1. The version file and the asset index, each checked against Mojang's own sha1.
    [self update:^(HZDownloadProgress *s) { s.phase = HZPhaseLooking; s.message = @"Asking Mojang what Minecraft needs..."; } force:YES];
    NSString *err = nil;
    NSData *manifest = [self fetchData:kManifestURL error:&err];
    if (!manifest) return [self fail:err ?: @"Could not reach Mojang."];
    NSDictionary *entry = [HZDownloader versionEntryIn:manifest version:self.version];
    if (!entry) return [self fail:[NSString stringWithFormat:@"Mojang's list has no usable Minecraft %@.", self.version]];
    NSData *versionJSON = [self fetchChecked:entry[@"url"] sha1:entry[@"sha1"] what:@"version file" error:&err];
    if (!versionJSON) return [self fail:err];

    HZDownloadPlan *plan = [HZDownloadPlan planGameFromVersionJSON:versionJSON version:self.version];
    if (plan.error) return [self fail:plan.error];
    NSDictionary *vroot = [NSJSONSerialization JSONObjectWithData:versionJSON options:0 error:nil];
    NSDictionary *ai = [vroot[@"assetIndex"] isKindOfClass:NSDictionary.class] ? vroot[@"assetIndex"] : nil;
    NSString *aiId = [ai[@"id"] isKindOfClass:NSString.class] ? ai[@"id"] : nil, *aiURL = ai[@"url"], *aiSha = ai[@"sha1"];
    if (!aiId.length || !aiURL.length || ![HZDownloadStore isHex:aiSha ?: @"" length:40] || [HZDownloadPlan safeRelativePath:aiId] == nil || [aiId containsString:@"/"]) {
        return [self fail:@"The version file has no usable asset index."];
    }
    NSData *indexJSON = [self fetchChecked:aiURL sha1:aiSha what:@"asset index" error:&err];
    if (!indexJSON) return [self fail:err];
    if (![plan addAssetsFromIndexJSON:indexJSON error:&err]) return [self fail:err ?: @"The asset index is not readable."];

    // The version file and asset index are small files the game folder also needs on disk.
    NSMutableArray<HZDownloadFile *> *all = [NSMutableArray arrayWithArray:plan.game];
    NSString *vpath = [NSString stringWithFormat:@"versions/%@/%@.json", self.version, self.version];
    NSString *ipath = [NSString stringWithFormat:@"assets/indexes/%@.json", aiId];
    [self writeSmall:versionJSON to:vpath];
    [self writeSmall:indexJSON to:ipath];
    [all addObjectsFromArray:plan.assets];

    // The server jar, from the same version file.
    if (self.includeServerJar) {
        NSDictionary *srv = vroot[@"downloads"][@"server"];
        NSString *surl = [srv[@"url"] isKindOfClass:NSString.class] ? srv[@"url"] : nil, *ssha = srv[@"sha1"];
        NSURL *su = surl ? [NSURL URLWithString:surl] : nil;
        if (su && [su.scheme isEqualToString:@"https"] && [HZDownloadPlan isMojangHost:su.host ?: @""] && [HZDownloadStore isHex:ssha ?: @"" length:40]) {
            HZDownloadFile *sf = [HZDownloadFile new];
            sf.url = surl; sf.sha1 = ssha; sf.path = [NSString stringWithFormat:@"versions/%@/%@-server.jar", self.version, self.version];
            id sz = srv[@"size"]; sf.size = [sz isKindOfClass:NSNumber.class] ? [sz unsignedLongLongValue] : 0;
            [all addObject:sf];
        } else {
            return [self fail:@"The version file has no usable server download."];
        }
    }

    unsigned long long total = 0;
    for (HZDownloadFile *f in all) total += f.size;

    // 2. What is already here and whole.
    [self update:^(HZDownloadProgress *s) {
        s.phase = HZPhaseChecking; s.filesTotal = all.count; s.bytesTotal = total; s.filesDone = 0; s.bytesDone = 0;
        s.message = @"Checking what is already on the phone...";
    } force:YES];
    NSMutableArray<HZDownloadFile *> *todo = [NSMutableArray new];
    for (HZDownloadFile *f in all) {
        if (self.cancelled) return [self finishCancelled];
        if ([self.store stateOfPath:f.path size:f.size sha1:f.sha1] == HZFileComplete) {
            [self update:^(HZDownloadProgress *s) { s.filesDone++; s.bytesDone += f.size; } force:NO];
        } else {
            [todo addObject:f];
        }
    }
    // 3. Room for the rest? Needs the bytes still to fetch plus a margin (hashing and renames).
    unsigned long long need = 0;
    for (HZDownloadFile *f in todo) need += f.size;
    unsigned long long free = [HZDownloadStore freeBytesAt:self.store.root];
    if (free > 0 && free < need + 100ull * 1024 * 1024) {
        return [self fail:[NSString stringWithFormat:@"Not enough space: %.0f MB still to download, %.0f MB free (plus about 100 MB of room to work).",
                           need / 1e6, free / 1e6]];
    }

    // 4. Fetch the rest, a few at a time.
    [self update:^(HZDownloadProgress *s) {
        s.phase = HZPhaseDownloading;
        s.message = todo.count ? [NSString stringWithFormat:@"Downloading %lu files...", (unsigned long)todo.count] : @"Everything is already here.";
    } force:YES];
    dispatch_group_t group = dispatch_group_create();
    dispatch_semaphore_t slots = dispatch_semaphore_create((long)[HZDownloader concurrency]);
    dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    __block NSString *firstError = nil;
    NSLock *errLock = [NSLock new];
    for (HZDownloadFile *f in todo) {
        dispatch_semaphore_wait(slots, DISPATCH_TIME_FOREVER);
        [errLock lock]; BOOL stop = self.cancelled || firstError != nil; [errLock unlock];
        if (stop) { dispatch_semaphore_signal(slots); break; }
        dispatch_group_async(group, q, ^{
            NSString *bad = [self fetchFile:f];
            if (bad) {
                [errLock lock]; if (!firstError && !self.cancelled) firstError = bad; [errLock unlock];
                if (!self.cancelled) self.cancelled = YES;   // one hard failure stops the others quickly
            } else {
                [self update:^(HZDownloadProgress *s) {
                    s.filesDone++; s.bytesDone += f.size;
                    s.message = [NSString stringWithFormat:@"Downloading... %@", f.path.lastPathComponent];
                } force:NO];
            }
            dispatch_semaphore_signal(slots);
        });
    }
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    [self.store removePartialFiles];

    if (firstError) { self.cancelled = NO; return [self fail:firstError]; }
    if (self.cancelled) return [self finishCancelled];
    self.running = NO;
    [self update:^(HZDownloadProgress *s) {
        s.phase = HZPhaseDone; s.filesDone = s.filesTotal; s.bytesDone = s.bytesTotal;
        s.message = @"Minecraft is on the phone and every file checked out.";
    } force:YES];
}

- (void)finishCancelled {
    [self.store removePartialFiles];
    self.running = NO;
    [self update:^(HZDownloadProgress *s) { s.phase = HZPhaseCancelled; s.message = @"Stopped. What finished is kept; start again to continue."; } force:YES];
}

// The version file and asset index are written whole (they are checked above) so a later step can
// read them from the game folder. Failure to write them is not fatal to the download itself.
- (void)writeSmall:(NSData *)data to:(NSString *)relative {
    NSString *path = [self.store absolutePathFor:relative];
    if (!path) return;
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
    [data writeToFile:path atomically:YES];
}

@end
