#import "DownloadStore.h"
#import <CommonCrypto/CommonDigest.h>

@implementation HZDownloadStore

- (instancetype)initWithRoot:(NSString *)root {
    if ((self = [super init])) {
        // Resolved once, so every later "is it inside the root" test compares real paths.
        _root = [[root stringByStandardizingPath] stringByResolvingSymlinksInPath];
    }
    return self;
}

- (NSString *)absolutePathFor:(NSString *)relativePath {
    if (relativePath.length == 0 || [relativePath hasPrefix:@"/"] || [relativePath containsString:@"\\"]) return nil;
    for (NSString *part in [relativePath componentsSeparatedByString:@"/"]) {
        if (part.length == 0 || [part isEqualToString:@"."] || [part isEqualToString:@".."]) return nil;
    }
    NSString *full = [self.root stringByAppendingPathComponent:relativePath];
    // The folder that will hold the file may not exist yet; resolve the deepest part that does, so a
    // symlink planted inside the root cannot lead the write out of it.
    NSString *dir = [full stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *existing = dir;
    NSMutableArray *rest = [NSMutableArray new];
    while (existing.length > 1 && ![fm fileExistsAtPath:existing]) {
        [rest insertObject:existing.lastPathComponent atIndex:0];
        existing = [existing stringByDeletingLastPathComponent];
    }
    NSString *resolved = [existing stringByResolvingSymlinksInPath];
    for (NSString *p in rest) resolved = [resolved stringByAppendingPathComponent:p];
    NSString *prefix = [self.root stringByAppendingString:@"/"];
    if (![[resolved stringByAppendingString:@"/"] hasPrefix:prefix]) return nil;
    return [resolved stringByAppendingPathComponent:full.lastPathComponent];
}

+ (BOOL)isHex:(NSString *)s length:(NSUInteger)n {
    if (s.length != n) return NO;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return NO;
    }
    return YES;
}

+ (NSString *)sha1OfFileAtPath:(NSString *)path {
    NSInputStream *in = [NSInputStream inputStreamWithFileAtPath:path];
    if (!in) return nil;
    [in open];
    CC_SHA1_CTX ctx;
    CC_SHA1_Init(&ctx);
    uint8_t buf[64 * 1024];
    BOOL failed = NO;
    for (;;) {
        NSInteger n = [in read:buf maxLength:sizeof buf];
        if (n < 0) { failed = YES; break; }
        if (n == 0) break;
        CC_SHA1_Update(&ctx, buf, (CC_LONG)n);
    }
    [in close];
    if (failed) return nil;
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &ctx);
    NSMutableString *hex = [NSMutableString stringWithCapacity:40];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

+ (unsigned long long)freeBytesAt:(NSString *)path {
    NSURL *u = [NSURL fileURLWithPath:path];
    NSDictionary *v = [u resourceValuesForKeys:@[NSURLVolumeAvailableCapacityForImportantUsageKey] error:nil];
    NSNumber *n = v[NSURLVolumeAvailableCapacityForImportantUsageKey];
    return n.longLongValue > 0 ? (unsigned long long)n.longLongValue : 0;
}

- (HZFileState)stateOfPath:(NSString *)relativePath size:(unsigned long long)size sha1:(NSString *)sha1 {
    NSString *path = [self absolutePathFor:relativePath];
    if (!path) return HZFileMissing;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    if (!attrs || ![attrs.fileType isEqualToString:NSFileTypeRegular]) {
        if (attrs) [fm removeItemAtPath:path error:nil];   // a folder or a link where a file belongs
        return HZFileMissing;
    }
    // Size first: it is free, and most wrong files are the wrong size. A listed size of 0 means
    // Mojang gave none; then only the hash decides.
    if (size > 0 && attrs.fileSize != size) { [fm removeItemAtPath:path error:nil]; return HZFileMissing; }
    NSString *have = [HZDownloadStore sha1OfFileAtPath:path];
    if (have && [have isEqualToString:sha1]) return HZFileComplete;
    [fm removeItemAtPath:path error:nil];
    return HZFileMissing;
}

- (NSString *)installDownloaded:(NSString *)temp toPath:(NSString *)relativePath
                           size:(unsigned long long)size sha1:(NSString *)sha1 {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dest = [self absolutePathFor:relativePath];
    if (!dest) { [fm removeItemAtPath:temp error:nil]; return @"A file's path would leave the game folder."; }
    NSDictionary *attrs = [fm attributesOfItemAtPath:temp error:nil];
    if (!attrs) return @"The downloaded file is missing.";
    if (size > 0 && attrs.fileSize != size) {
        [fm removeItemAtPath:temp error:nil];
        return [NSString stringWithFormat:@"%@ is %llu bytes, Mojang lists %llu.", relativePath.lastPathComponent, attrs.fileSize, size];
    }
    NSString *have = [HZDownloadStore sha1OfFileAtPath:temp];
    if (!have || ![have isEqualToString:sha1]) {
        [fm removeItemAtPath:temp error:nil];
        return [NSString stringWithFormat:@"%@ does not match the checksum Mojang lists.", relativePath.lastPathComponent];
    }
    NSError *e = nil;
    [fm createDirectoryAtPath:[dest stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&e];
    if (e) { [fm removeItemAtPath:temp error:nil]; return e.localizedDescription; }
    [fm removeItemAtPath:dest error:nil];
    // Same volume (the temp is made beside the destination by Downloader), so this is a rename and
    // the real name never holds half a file.
    if (![fm moveItemAtPath:temp toPath:dest error:&e]) {
        [fm removeItemAtPath:temp error:nil];
        return e.localizedDescription ?: @"Could not move the file into place.";
    }
    return nil;
}

- (NSUInteger)removePartialFiles {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:self.root];
    NSMutableArray *doomed = [NSMutableArray new];
    for (NSString *rel in en) if ([rel hasSuffix:@".part"]) [doomed addObject:rel];
    for (NSString *rel in doomed) [fm removeItemAtPath:[self.root stringByAppendingPathComponent:rel] error:nil];
    return doomed.count;
}

@end
