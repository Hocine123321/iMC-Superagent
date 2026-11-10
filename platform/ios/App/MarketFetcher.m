#import "MarketFetcher.h"

@interface HZMarketFetcher () <NSURLSessionDownloadDelegate, NSURLSessionTaskDelegate>
@property (strong) NSURLSession *session;
@property (strong) NSURLSessionDownloadTask *task;
@property (copy) void (^progress)(double);
@property (copy) void (^done)(NSString *, NSString *);
@property (copy) NSString *stagingDir;
@property (nonatomic) unsigned long long expected;
@property (nonatomic) NSUInteger redirects;
@property (nonatomic) BOOL finished;
@property (copy) NSString *refusal;   // set when the delegate cancels the task on purpose
@end

@implementation HZMarketFetcher

+ (BOOL)isAllowedRedirectHost:(NSString *)host scheme:(NSString *)scheme {
    if (![scheme.lowercaseString isEqualToString:@"https"]) return NO;
    NSString *h = host.lowercaseString;
    return [h isEqualToString:@"github.com"] || [h isEqualToString:@"githubusercontent.com"] || [h hasSuffix:@".githubusercontent.com"];
}

- (void)fetch:(HZMarketFile *)file stagingDir:(NSString *)stagingDir progress:(void (^)(double))progress done:(void (^)(NSString *, NSString *))done {
    self.progress = progress; self.done = done; self.stagingDir = stagingDir; self.expected = file.size;
    if (![HZMarketIndex isRegistryFileURL:file.url]) { [self finishWith:nil error:@"The file is not on the registry's release address."]; return; }
    NSURL *url = [NSURL URLWithString:file.url];
    if (!url) { [self finishWith:nil error:@"The file address is not valid."]; return; }
    NSError *err = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:stagingDir withIntermediateDirectories:YES attributes:nil error:&err];
    if (err) { [self finishWith:nil error:err.localizedDescription]; return; }

    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.timeoutIntervalForRequest = 120;
    cfg.timeoutIntervalForResource = 900;
    cfg.HTTPCookieStorage = nil;
    cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    self.session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:NSOperationQueue.mainQueue];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:@"iMC-Horizon-iOS (github.com/Hocine123321/iMC-Superagent)" forHTTPHeaderField:@"User-Agent"];
    self.task = [self.session downloadTaskWithRequest:req];
    [self.task resume];
}

- (void)cancel {
    self.refusal = @"Stopped.";
    [self.task cancel];
}

- (void)finishWith:(NSString *)path error:(NSString *)error {
    if (self.finished) return;
    self.finished = YES;
    void (^d)(NSString *, NSString *) = self.done;
    self.done = nil; self.progress = nil;
    [self.session finishTasksAndInvalidate];
    if (d) dispatch_async(dispatch_get_main_queue(), ^{ d(path, error); });
}

#pragma mark - delegate

- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t willPerformHTTPRedirection:(NSHTTPURLResponse *)r newRequest:(NSURLRequest *)req completionHandler:(void (^)(NSURLRequest *))handler {
    self.redirects++;
    NSURL *to = req.URL;
    if (self.redirects > 5 || !to || ![HZMarketFetcher isAllowedRedirectHost:to.host ?: @"" scheme:to.scheme ?: @""]) {
        self.refusal = [NSString stringWithFormat:@"The download was sent to %@, which the app does not allow.", to.host ?: @"an unknown address"];
        handler(nil);       // do not follow
        [t cancel];
        return;
    }
    handler(req);
}

- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)t didWriteData:(int64_t)n totalBytesWritten:(int64_t)total totalBytesExpectedToWrite:(int64_t)of {
    // Cut off a server that sends more than the index lists.
    if (self.expected && (unsigned long long)total > self.expected) {
        self.refusal = @"The server sent more data than the registry lists. Nothing was installed.";
        [t cancel];
        return;
    }
    double denom = self.expected ? (double)self.expected : (of > 0 ? (double)of : 0);
    if (denom > 0 && self.progress) self.progress(MIN(1.0, (double)total / denom));
}

- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)t didFinishDownloadingToURL:(NSURL *)location {
    NSHTTPURLResponse *resp = [t.response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)t.response : nil;
    if (!resp || resp.statusCode != 200) {
        [self finishWith:nil error:[NSString stringWithFormat:@"The server answered %ld.", (long)resp.statusCode]];
        return;
    }
    // Move out of the system's temp file before this method returns (the system deletes it after).
    NSString *dest = [self.stagingDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.part", NSUUID.UUID.UUIDString]];
    NSError *err = nil;
    [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
    if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:dest] error:&err]) {
        [self finishWith:nil error:err.localizedDescription ?: @"Could not keep the download."];
        return;
    }
    [self finishWith:dest error:nil];
}

- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)error {
    if (!error) return;     // success was reported by didFinishDownloadingToURL
    if (self.refusal) { [self finishWith:nil error:self.refusal]; return; }
    if (error.code == NSURLErrorCancelled) { [self finishWith:nil error:@"Stopped."]; return; }
    [self finishWith:nil error:error.localizedDescription];
}

@end
