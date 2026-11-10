#import "FileBrowser.h"

@implementation HZFileEntry
@end

@implementation HZFileBrowser

- (instancetype)initWithRoot:(NSString *)root {
    if ((self = [super init])) {
        _root = [[root stringByStandardizingPath] stringByResolvingSymlinksInPath];
    }
    return self;
}

+ (NSString *)parentOf:(NSString *)p {
    NSRange r = [p rangeOfString:@"/" options:NSBackwardsSearch];
    return r.location == NSNotFound ? @"" : [p substringToIndex:r.location];
}
+ (NSString *)join:(NSString *)folder name:(NSString *)name {
    return folder.length ? [folder stringByAppendingFormat:@"/%@", name] : name;
}

// The syntax rule, before the disk is touched. "" is the root.
static BOOL SyntaxOK(NSString *p) {
    if (p.length == 0) return YES;
    if ([p hasPrefix:@"/"] || [p containsString:@"\\"] || [p containsString:@"\0"]) return NO;
    for (NSString *part in [p componentsSeparatedByString:@"/"]) {
        if (part.length == 0 || [part isEqualToString:@"."] || [part isEqualToString:@".."]) return NO;
    }
    return YES;
}

- (NSString *)resolve:(NSString *)relativePath {
    if (!SyntaxOK(relativePath)) return nil;
    if (relativePath.length == 0) return self.root;
    NSString *full = [self.root stringByAppendingPathComponent:relativePath];
    NSFileManager *fm = [NSFileManager defaultManager];
    // Resolve the folder that holds it (that may be a link inside the root pointing out), then add the
    // last name back. The last name itself is not followed, so a link can be listed, renamed and
    // deleted as a link without ever reaching its target.
    NSString *dir = [[full stringByDeletingLastPathComponent] stringByResolvingSymlinksInPath];
    NSString *resolved = [dir stringByAppendingPathComponent:full.lastPathComponent];
    NSString *prefix = [self.root stringByAppendingString:@"/"];
    if (![resolved hasPrefix:prefix]) return nil;
    (void)fm;
    return resolved;
}

// Whether an existing path is a link (so it is never walked into).
static BOOL IsLink(NSString *path) {
    NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    return [a.fileType isEqualToString:NSFileTypeSymbolicLink];
}

- (NSArray<HZFileEntry *> *)listFolder:(NSString *)relativePath error:(NSString **)error {
    NSString *path = [self resolve:relativePath];
    if (!path) { if (error) *error = @"That folder is outside the Horizon folder."; return nil; }
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir] || !isDir || IsLink(path)) {
        if (error) *error = @"That is not a folder."; return nil;
    }
    NSError *e = nil;
    NSArray *names = [fm contentsOfDirectoryAtPath:path error:&e];
    if (!names) { if (error) *error = e.localizedDescription; return nil; }
    NSMutableArray<HZFileEntry *> *out = [NSMutableArray new];
    for (NSString *n in names) {
        NSString *child = [path stringByAppendingPathComponent:n];
        NSDictionary *a = [fm attributesOfItemAtPath:child error:nil];
        if (!a) continue;
        HZFileEntry *en = [HZFileEntry new];
        en.name = n;
        en.relativePath = [HZFileBrowser join:relativePath name:n];
        // A link counts as a file here: the screen never opens it as a folder.
        en.isFolder = [a.fileType isEqualToString:NSFileTypeDirectory];
        en.size = en.isFolder ? 0 : a.fileSize;
        en.modified = a.fileModificationDate;
        [out addObject:en];
    }
    [out sortUsingComparator:^NSComparisonResult(HZFileEntry *x, HZFileEntry *y) {
        if (x.isFolder != y.isFolder) return x.isFolder ? NSOrderedAscending : NSOrderedDescending;
        return [x.name caseInsensitiveCompare:y.name];
    }];
    return out;
}

- (unsigned long long)sizeOf:(NSString *)relativePath {
    NSString *path = [self resolve:relativePath];
    if (!path) return 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *a = [fm attributesOfItemAtPath:path error:nil];
    if (!a) return 0;
    if (![a.fileType isEqualToString:NSFileTypeDirectory]) return a.fileSize;
    unsigned long long total = 0;
    // enumeratorAtPath does not follow links to folders.
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:path];
    for (NSString *rel in en) {
        NSDictionary *ca = [fm attributesOfItemAtPath:[path stringByAppendingPathComponent:rel] error:nil];
        if (ca && [ca.fileType isEqualToString:NSFileTypeRegular]) total += ca.fileSize;
    }
    return total;
}

- (HZDeleteRisk)deleteRiskOf:(NSString *)p {
    if (p.length == 0) return HZDeleteForbidden;
    NSString *l = p.lowercaseString;
    // The sign-in record and anything named for it.
    if ([l isEqualToString:@"account.txt"]) return HZDeleteAccount;
    // The player's worlds: home/saves itself and everything under it.
    if ([l isEqualToString:@"home/saves"] || [l hasPrefix:@"home/saves/"]) return HZDeleteWorld;
    // The prepared game files and the downloaded Minecraft.
    if ([l isEqualToString:@"resources"] || [l hasPrefix:@"resources/"] ||
        [l isEqualToString:@"minecraft"] || [l hasPrefix:@"minecraft/"]) return HZDeleteGameFiles;
    // The folder that holds the saves, options and logs: deleting it deletes the worlds.
    if ([l isEqualToString:@"home"]) return HZDeleteWorld;
    return HZDeleteOrdinary;
}

+ (NSString *)warningForRisk:(HZDeleteRisk)risk name:(NSString *)name size:(unsigned long long)size {
    NSString *sz = [NSByteCountFormatter stringFromByteCount:(long long)size countStyle:NSByteCountFormatterCountStyleFile];
    switch (risk) {
        case HZDeleteOrdinary:
            return [NSString stringWithFormat:@"Delete %@ (%@)? This cannot be undone.", name, sz];
        case HZDeleteWorld:
            return [NSString stringWithFormat:@"%@ (%@) holds your worlds. If you delete it they are gone for good, and nothing can bring them back. "
                    @"Export a copy first if you might want them.", name, sz];
        case HZDeleteGameFiles:
            return [NSString stringWithFormat:@"%@ (%@) is the game itself. The game will not start until it is downloaded or imported again.", name, sz];
        case HZDeleteAccount:
            return @"This is your sign-in record. Deleting it signs you out of the app. Use the Account screen to sign out properly.";
        case HZDeleteForbidden:
            return @"The Horizon folder itself cannot be deleted.";
    }
}

+ (NSString *)problemWithName:(NSString *)name {
    if (name.length == 0) return @"The name is empty.";
    if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) return @"That name is not allowed.";
    if ([name containsString:@"/"] || [name containsString:@"\\"]) return @"A name cannot contain a slash.";
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar c = [name characterAtIndex:i];
        if (c < 0x20 || c == 0x7f) return @"A name cannot contain control characters.";
    }
    if ([name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 255) return @"The name is too long.";
    return nil;
}

- (NSString *)deletePath:(NSString *)relativePath {
    if ([self deleteRiskOf:relativePath] == HZDeleteForbidden) return @"The Horizon folder itself cannot be deleted.";
    NSString *path = [self resolve:relativePath];
    if (!path) return @"That path is outside the Horizon folder.";
    NSError *e = nil;
    // removeItemAtPath: on a link removes the link, never its target.
    if (![[NSFileManager defaultManager] removeItemAtPath:path error:&e]) return e.localizedDescription;
    return nil;
}

- (NSString *)renamePath:(NSString *)relativePath to:(NSString *)newName {
    NSString *bad = [HZFileBrowser problemWithName:newName];
    if (bad) return bad;
    if (relativePath.length == 0) return @"The Horizon folder cannot be renamed.";
    NSString *from = [self resolve:relativePath];
    NSString *toRel = [HZFileBrowser join:[HZFileBrowser parentOf:relativePath] name:newName];
    NSString *to = [self resolve:toRel];
    if (!from || !to) return @"That path is outside the Horizon folder.";
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:to] || IsLink(to)) return @"Something with that name is already there.";
    NSError *e = nil;
    if (![fm moveItemAtPath:from toPath:to error:&e]) return e.localizedDescription;
    return nil;
}

- (NSString *)createFolderNamed:(NSString *)name inside:(NSString *)relativeFolder {
    NSString *bad = [HZFileBrowser problemWithName:name];
    if (bad) return bad;
    NSString *parent = [self resolve:relativeFolder];
    NSString *path = [self resolve:[HZFileBrowser join:relativeFolder name:name]];
    if (!parent || !path) return @"That path is outside the Horizon folder.";
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path] || IsLink(path)) return @"Something with that name is already there.";
    NSError *e = nil;
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:&e]) return e.localizedDescription;
    return nil;
}

@end
