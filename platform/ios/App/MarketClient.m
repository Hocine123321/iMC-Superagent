#import "MarketClient.h"

static NSString *const kIndexURL = @"https://horizon-rust.github.io/horizon-mods/index.json";
static NSString *const kCacheName = @"horizon-index.json";

@implementation HZMarketResult
@end

@interface HZMarketClient ()
@property (copy) NSString *dir;
@property (strong) NSURLSession *session;
@end

@implementation HZMarketClient

+ (NSString *)indexURL { return kIndexURL; }
+ (NSTimeInterval)freshSeconds { return 600; }

- (instancetype)initWithCacheDirectory:(NSString *)cacheDirectory {
    if ((self = [super init])) {
        _dir = [cacheDirectory copy];
        NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        cfg.timeoutIntervalForRequest = 20;
        cfg.timeoutIntervalForResource = 60;
        cfg.HTTPCookieStorage = nil;
        cfg.URLCredentialStorage = nil;
        cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

- (NSString *)cachePath { return [self.dir stringByAppendingPathComponent:kCacheName]; }

// The saved copy and when it was saved, if it still parses (a damaged cache is treated as none).
- (HZMarketIndex *)readCache:(NSDate **)when {
    NSData *d = [NSData dataWithContentsOfFile:[self cachePath]];
    if (!d) return nil;
    HZMarketIndex *ix = [HZMarketIndex parse:d error:nil];
    if (ix && when) *when = [[NSFileManager defaultManager] attributesOfItemAtPath:[self cachePath] error:nil].fileModificationDate;
    return ix;
}

- (void)loadForce:(BOOL)force completion:(void (^)(HZMarketResult *))done {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        HZMarketResult *r = [self load:force];
        dispatch_async(dispatch_get_main_queue(), ^{ done(r); });
    });
}

// Always off the main thread (it waits for the network).
- (HZMarketResult *)load:(BOOL)force {
    HZMarketResult *r = [HZMarketResult new];
    NSDate *when = nil;
    HZMarketIndex *cached = [self readCache:&when];
    if (cached && !force && when && [[NSDate date] timeIntervalSinceDate:when] >= 0 &&
        [[NSDate date] timeIntervalSinceDate:when] < [HZMarketClient freshSeconds]) {
        r.index = cached; r.source = HZMarketCached; r.fetched = when;
        return r;
    }

    NSString *why = nil;
    NSData *body = [self fetch:&why];
    if (body) {
        NSString *bad = nil;
        HZMarketIndex *fresh = [HZMarketIndex parse:body error:&bad];
        if (fresh) {
            // Parsed and checked: only now does it replace the cache (atomically, so a crash leaves the old file).
            [[NSFileManager defaultManager] createDirectoryAtPath:self.dir withIntermediateDirectories:YES attributes:nil error:nil];
            [body writeToFile:[self cachePath] atomically:YES];
            r.index = fresh; r.source = HZMarketFresh; r.fetched = [NSDate date];
            return r;
        }
        why = bad;
    }
    // The registry could not be used: fall back to the older copy, and say why.
    if (cached) {
        r.index = cached; r.source = HZMarketOffline; r.fetched = when; r.error = why;
        return r;
    }
    r.error = why ?: @"The Marketplace could not be loaded.";
    return r;
}

// One GET of the fixed address, refusing anything that grows past the cap. nil with `why` set on failure.
- (NSData *)fetch:(NSString **)why {
    NSURL *url = [NSURL URLWithString:kIndexURL];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSData *body = nil; __block NSInteger status = 0; __block NSError *err = nil;
    NSURLSessionDataTask *t = [self.session dataTaskWithURL:url completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        body = d; err = e; status = [resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        dispatch_semaphore_signal(done);
    }];
    [t resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (err) { *why = @"The Marketplace can't be reached. Check your connection."; return nil; }
    if (status != 200) { *why = [NSString stringWithFormat:@"The registry answered %ld.", (long)status]; return nil; }
    // The size cap is applied to the finished body by MarketIndex (over 16 MiB is refused); the
    // request timeout of 60 seconds bounds how long a slow or endless answer can occupy the app.
    if (body.length == 0) { *why = @"The registry sent nothing."; return nil; }
    return body;
}

@end
