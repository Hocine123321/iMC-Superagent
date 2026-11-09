#import "LauncherModel.h"

@implementation HZLauncherModel {
    NSString *_root, *_resources, *_home;
}

+ (instancetype)shared {
    static HZLauncherModel *m; static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [HZLauncherModel new]; });
    return m;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        _root = [docs stringByAppendingPathComponent:@"Horizon"];
        _resources = [_root stringByAppendingPathComponent:@"resources"];
        _home = [_root stringByAppendingPathComponent:@"home"];
    }
    return self;
}
- (NSString *)root { return _root; }
- (NSString *)resources { return _resources; }
- (NSString *)home { return _home; }

// The engine's rules (loading_screen.rs: missing_resources and damaged_prepared):
//  1. horizon-resources.json must be a file;
//  2. it must not be empty and must be valid JSON;
//  3. no other top-level .json file may be empty.
- (HZFilesState)checkFiles:(NSString **)problem {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *manifest = [_resources stringByAppendingPathComponent:@"horizon-resources.json"];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:manifest isDirectory:&isDir] || isDir) {
        if (problem) *problem = @"horizon-resources.json is not in the resources folder.";
        return HZFilesMissing;
    }
    NSData *data = [NSData dataWithContentsOfFile:manifest];
    // Empty means nothing but ASCII whitespace, as the engine tests it (`all(is_ascii_whitespace)`).
    BOOL blank = YES;
    const unsigned char *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length && blank; i++) {
        unsigned char c = bytes[i];
        blank = (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f');
    }
    if (blank) {
        if (problem) *problem = @"horizon-resources.json is empty.";
        return HZFilesDamaged;
    }
    if (![NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil]) {
        if (problem) *problem = @"horizon-resources.json is not valid JSON.";
        return HZFilesDamaged;
    }
    for (NSString *name in [fm contentsOfDirectoryAtPath:_resources error:nil]) {
        if (![name.pathExtension isEqualToString:@"json"]) continue;
        NSDictionary *a = [fm attributesOfItemAtPath:[_resources stringByAppendingPathComponent:name] error:nil];
        if (a && [a fileSize] == 0) {
            if (problem) *problem = [NSString stringWithFormat:@"%@ is empty.", name];
            return HZFilesDamaged;
        }
    }
    if (problem) *problem = nil;
    return HZFilesReady;
}

- (unsigned long long)resourcesSize {
    unsigned long long total = 0;
    NSDirectoryEnumerator *e = [[NSFileManager defaultManager] enumeratorAtPath:_resources];
    for (NSString *rel in e) {
        (void)rel;
        NSDictionary *a = e.fileAttributes;
        if ([a.fileType isEqualToString:NSFileTypeRegular]) total += a.fileSize;
    }
    return total;
}

- (NSUInteger)topLevelItemCount {
    return [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_resources error:nil].count;
}

- (NSString *)flagPath { return [_root stringByAppendingPathComponent:@"start-game"]; }

- (BOOL)setStartGameFlag {
    return [@"" writeToFile:[self flagPath] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (NSString *)settingsPath { return [_root stringByAppendingPathComponent:@"launcher.txt"]; }

- (BOOL)opensGameDirectly {
    NSString *text = [NSString stringWithContentsOfFile:[self settingsPath] encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"openGame:"]) return [[line substringFromIndex:9] hasPrefix:@"1"];
    }
    return NO;
}

- (void)setOpensGameDirectly:(BOOL)on {
    NSString *text = [NSString stringWithFormat:@"openGame:%d\n", on ? 1 : 0];
    [text writeToFile:[self settingsPath] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (BOOL)shouldSkipLauncher {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![self opensGameDirectly]) return NO;
    if ([fm fileExistsAtPath:[_root stringByAppendingPathComponent:@"open-launcher"]]) return NO;
    // The previous run's report, read before this run's crash reporter replaces it.
    NSString *crash = [NSString stringWithContentsOfFile:[_root stringByAppendingPathComponent:@"crash.txt"]
                                                encoding:NSUTF8StringEncoding error:nil] ?: @"";
    // A real crash brings the launcher back, so the report can be read and shared.
    if ([crash containsString:@"=== FATAL SIGNAL"] || [crash containsString:@"=== UNCAUGHT"]) return NO;
    // A run that just ended (stopped from a debugger, swiped away, killed by the system) is not a
    // crash: an iPhone app is almost never closed "cleanly", so refusing here made the feature
    // fail on most launches. Three such ends in a row look like a kill loop, which brings the
    // launcher back too. (Two would catch your quick open-look-stop tests.) The crash reporter
    // keeps the count (`unclean-ends`) and ends it after a run of fifteen seconds.
    NSString *count = [NSString stringWithContentsOfFile:[_root stringByAppendingPathComponent:@"unclean-ends"]
                                                encoding:NSUTF8StringEncoding error:nil];
    // The marker of the run that just ended is counted by the crash reporter, which has not run
    // yet in this launch: it will make the count one higher, so three means "the fourth in a row".
    BOOL markerLeft = [fm fileExistsAtPath:[_root stringByAppendingPathComponent:@".running"]];
    if (count.integerValue + (markerLeft ? 1 : 0) >= 3) return NO;
    return [self checkFiles:nil] == HZFilesReady;
}

- (BOOL)consumeStartGameFlag {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:[self flagPath]]) return NO;
    [fm removeItemAtPath:[self flagPath] error:nil];
    return YES;
}

- (void)importFolderAtURL:(NSURL *)source
               completion:(void (^)(NSError *))completion
                 progress:(void (^)(double, NSString *))progress {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL scoped = [source startAccessingSecurityScopedResource];
        NSError *error = nil;
        // A picked folder may be the version folder itself (horizon-resources.json inside) or
        // contain it one level down (the player picked "horizon-client" or "26.3" 's parent).
        NSURL *base = source;
        if (![fm fileExistsAtPath:[source.path stringByAppendingPathComponent:@"horizon-resources.json"]]) {
            for (NSURL *child in [fm contentsOfDirectoryAtURL:source includingPropertiesForKeys:nil options:0 error:nil]) {
                if ([fm fileExistsAtPath:[child.path stringByAppendingPathComponent:@"horizon-resources.json"]]) { base = child; break; }
            }
        }
        if (![fm fileExistsAtPath:[base.path stringByAppendingPathComponent:@"horizon-resources.json"]]) {
            error = [NSError errorWithDomain:@"iMCHorizon" code:1 userInfo:@{NSLocalizedDescriptionKey:
                @"That folder has no horizon-resources.json. Pick the folder that contains it (for example 26.3)."}];
        }
        unsigned long long needed = 0;
        if (!error) {
            // Count first, so progress is a fraction of the real work, and the size, because the
            // copy is made beside the old files (a failed import must leave them alone).
            NSDirectoryEnumerator *sizer = [fm enumeratorAtPath:base.path];
            for (NSString *rel in sizer) {
                (void)rel;
                if ([sizer.fileAttributes.fileType isEqualToString:NSFileTypeRegular]) needed += sizer.fileAttributes.fileSize;
            }
            NSDictionary *fs = [fm attributesOfFileSystemForPath:_root error:nil];
            unsigned long long freeBytes = [fs[NSFileSystemFreeSize] unsignedLongLongValue];
            // The old files stay until the new copy is complete, so both are on the disk at once.
            if (freeBytes && freeBytes < needed + (200ull << 20)) {
                error = [NSError errorWithDomain:@"iMCHorizon" code:2 userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Not enough free space: the files need %.0f MB and the phone has %.0f MB free.",
                        needed / 1048576.0, freeBytes / 1048576.0]}];
            }
        }
        if (!error) {
            NSUInteger total = 0;
            for (NSString *rel in [fm enumeratorAtPath:base.path]) { (void)rel; total++; }
            NSString *staging = [_root stringByAppendingPathComponent:@"resources.importing"];
            [fm removeItemAtPath:staging error:nil];
            [fm createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:&error];
            NSUInteger done = 0;
            if (!error) {
                NSDirectoryEnumerator *en = [fm enumeratorAtPath:base.path];
                for (NSString *rel in en) {
                    NSString *from = [base.path stringByAppendingPathComponent:rel];
                    NSString *to = [staging stringByAppendingPathComponent:rel];
                    BOOL dir = [en.fileAttributes.fileType isEqualToString:NSFileTypeDirectory];
                    if (dir) { [fm createDirectoryAtPath:to withIntermediateDirectories:YES attributes:nil error:nil]; }
                    else if (![fm copyItemAtPath:from toPath:to error:&error]) { break; }
                    done++;
                    if (progress && (done % 50 == 0 || done == total)) {
                        double f = total ? (double)done / total : 1; NSString *name = rel.lastPathComponent;
                        dispatch_async(dispatch_get_main_queue(), ^{ progress(f, name); });
                    }
                }
            }
            if (!error) {
                // Swap only after a complete copy, so a failed import leaves the old files alone.
                [fm removeItemAtPath:_resources error:nil];
                [fm moveItemAtPath:staging toPath:_resources error:&error];
            } else {
                [fm removeItemAtPath:staging error:nil];
            }
        }
        if (scoped) [source stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
    });
}

- (NSString *)readTail:(NSString *)path maxBytes:(NSUInteger)max {
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d) return nil;
    if (d.length > max) d = [d subdataWithRange:NSMakeRange(d.length - max, max)];
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}
// The newest file in a folder with the given extension, or nil.
- (NSString *)newestFileIn:(NSString *)dir extension:(NSString *)ext {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *best = nil; NSDate *bestDate = nil;
    for (NSString *n in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        if (ext && ![n.pathExtension isEqualToString:ext]) continue;
        NSString *p = [dir stringByAppendingPathComponent:n];
        NSDate *m = [fm attributesOfItemAtPath:p error:nil].fileModificationDate;
        if (m && (!bestDate || [m compare:bestDate] == NSOrderedDescending)) { best = p; bestDate = m; }
    }
    return best;
}
// Two kinds of crash leave a report: a native one (signal, Objective-C exception) in crash.txt,
// written by CrashReporter.m, and a Rust panic in <home>/crash-reports/ (the engine's own).
// Whichever is newer is the one the person wants.
- (NSString *)newestCrashPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *native = [_root stringByAppendingPathComponent:@"crash.txt"];
    NSString *rust = [self newestFileIn:[_home stringByAppendingPathComponent:@"crash-reports"] extension:nil];
    NSDate *nd = [fm attributesOfItemAtPath:native error:nil].fileModificationDate;
    NSDate *rd = rust ? [fm attributesOfItemAtPath:rust error:nil].fileModificationDate : nil;
    // crash.txt is rewritten at every launch, so it is only a crash report if it has a signal or
    // an exception in it; otherwise it is just this launch's header.
    NSString *nativeText = nd ? [NSString stringWithContentsOfFile:native encoding:NSUTF8StringEncoding error:nil] : nil;
    BOOL nativeIsCrash = [nativeText containsString:@"=== FATAL SIGNAL"] || [nativeText containsString:@"=== UNCAUGHT"];
    if (nativeIsCrash && (!rd || [nd compare:rd] != NSOrderedAscending)) return native;
    if (rust) return rust;
    NSString *previous = [_root stringByAppendingPathComponent:@"crash-previous.txt"];
    return [fm fileExistsAtPath:previous] ? previous : (nativeIsCrash ? native : nil);
}
- (NSString *)crashReportText {
    NSString *p = [self newestCrashPath];
    return p ? [self readTail:p maxBytes:20000] : nil;
}
// The engine writes <home>/logs/latest.log (its own launch-api documentation says so).
- (NSString *)newestLog {
    NSString *p = [[_home stringByAppendingPathComponent:@"logs"] stringByAppendingPathComponent:@"latest.log"];
    return [[NSFileManager defaultManager] fileExistsAtPath:p] ? p : nil;
}
- (NSString *)gameLogText {
    NSString *p = [self newestLog];
    return p ? [self readTail:p maxBytes:20000] : nil;
}
- (NSArray<NSURL *> *)diagnosticFiles {
    NSMutableArray *out = [NSMutableArray new];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *p in @[[_root stringByAppendingPathComponent:@"crash.txt"],
                          [_root stringByAppendingPathComponent:@"crash-previous.txt"],
                          [self newestFileIn:[_home stringByAppendingPathComponent:@"crash-reports"] extension:nil] ?: @"",
                          [_root stringByAppendingPathComponent:@"diagnostics.txt"],
                          [_root stringByAppendingPathComponent:@"session-log.csv"],
                          [_root stringByAppendingPathComponent:@"session-log-previous.csv"],
                          [self newestLog] ?: @""]) {
        if (p.length && [fm fileExistsAtPath:p]) [out addObject:[NSURL fileURLWithPath:p]];
    }
    return out;
}
@end
