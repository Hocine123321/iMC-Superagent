#import "LauncherTheme.h"
#import "LauncherModel.h"

static UIColor *Dyn(UIColor *dark, UIColor *light) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleLight ? light : dark;
    }];
}

NSNotificationName const HZThemeChanged = @"HZThemeChanged";

@implementation HZTheme

// Navy in dark mode, a pale blue-white in light mode: the same ground the SwiftUI backdrop starts from.
+ (UIColor *)background {
    return Dyn([UIColor colorWithRed:0.027 green:0.043 blue:0.110 alpha:1], [UIColor colorWithRed:0.949 green:0.961 blue:0.992 alpha:1]);
}

#pragma mark - Settings file

+ (NSString *)settingsPath { return [[HZLauncherModel shared].root stringByAppendingPathComponent:@"launcher.txt"]; }

// launcher.txt is read all over the launcher (every Marketplace row asks "compact lists?", every haptic asks for
// "haptics", the backdrop asks for the mix) and the first version re-read and re-parsed the file for each question,
// and wrote it again (read, edit, atomic write) for every tick of a slider. A drag of the "Backdrop colour" slider
// was sixty file rewrites a second on the main thread.
//
// Now the parsed lines are kept in memory, tagged with the file's modification date and size, so an edit by hand or
// by the other writers of this file (LauncherModel.m, main.m reads it before anything exists) is noticed: a stat
// call, not a read. Writes change the memory at once and reach the disk on a utility queue, the latest value of a
// key winning, so a drag is one write. Anything that reads the file directly calls +flushSettings first.
static NSMutableDictionary<NSString *, NSString *> *gSettings;   // key -> value, the file's own lines
static NSMutableArray<NSString *> *gOrder;                       // keys in file order, to keep it stable
static NSDate *gStamp;                                           // modification date the memory was read at
static unsigned long long gStampSize;
static BOOL gDirty;                                              // memory is ahead of the disk
static BOOL gFlushQueued;
static dispatch_queue_t gQueue;                                  // serial: the file is only written here
static NSObject *gLock;

static void SettingsInit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gLock = [NSObject new];
        gQueue = dispatch_queue_create("dev.imc.settings", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(gQueue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    });
}

// Caller holds gLock.
static void LoadIfChanged(NSString *path) {
    NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSDate *when = a[NSFileModificationDate];
    unsigned long long size = [a fileSize];
    if (gSettings && !gDirty && ((when == nil && gStamp == nil) || [when isEqualToDate:gStamp]) && size == gStampSize) return;
    if (gSettings && gDirty) return;   // our own unwritten changes are newer than the disk
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
    gSettings = [NSMutableDictionary dictionary];
    gOrder = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSRange colon = [line rangeOfString:@":"];
        if (!line.length) continue;
        if (colon.location == NSNotFound) {          // not a key:value line: kept as it is, as the old rewrite did
            NSString *k = [NSString stringWithFormat:@"\x01%lu", (unsigned long)gOrder.count];
            [gOrder addObject:k];
            gSettings[k] = line;
            continue;
        }
        NSString *k = [line substringToIndex:colon.location];
        if (!gSettings[k]) [gOrder addObject:k];
        gSettings[k] = [line substringFromIndex:colon.location + 1];
    }
    gStamp = when;
    gStampSize = size;
}

// Caller holds gLock. Writes the memory to the file.
static void WriteNow(NSString *path, NSString *root) {
    NSMutableString *out = [NSMutableString string];
    for (NSString *k in gOrder) {
        if ([k hasPrefix:@"\x01"]) [out appendFormat:@"%@\n", gSettings[k]];
        else [out appendFormat:@"%@:%@\n", k, gSettings[k]];
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    gStamp = a[NSFileModificationDate];
    gStampSize = [a fileSize];
    gDirty = NO;
}

+ (void)flushSettings {
    SettingsInit();
    NSString *root = [HZLauncherModel shared].root, *path = [self settingsPath];
    @synchronized (gLock) { if (gDirty) WriteNow(path, root); }
}

+ (NSString *)settingFor:(NSString *)key {
    SettingsInit();
    NSString *path = [self settingsPath];
    @synchronized (gLock) {
        LoadIfChanged(path);
        return gSettings[key];
    }
}

+ (void)setSetting:(NSString *)value for:(NSString *)key {
    SettingsInit();
    NSString *path = [self settingsPath], *root = [HZLauncherModel shared].root;
    BOOL queue = NO;
    @synchronized (gLock) {
        LoadIfChanged(path);
        if (!gSettings[key]) [gOrder addObject:key];
        else if ([gSettings[key] isEqualToString:value]) return;       // nothing changed: no write at all
        gSettings[key] = value;
        gDirty = YES;
        if (!gFlushQueued) { gFlushQueued = YES; queue = YES; }
    }
    if (queue) {
        // A short delay lets the rest of a slider drag land in the same write.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), gQueue, ^{
            @synchronized (gLock) { gFlushQueued = NO; if (gDirty) WriteNow(path, root); }
        });
    }
}

+ (void)forgetSettings {
    SettingsInit();
    @synchronized (gLock) { gSettings = nil; gOrder = nil; gStamp = nil; gStampSize = 0; gDirty = NO; }
}

#pragma mark - Appearance

+ (HZAppearance)appearance {
    NSString *v = [self settingFor:@"appearance"];
    if ([v hasPrefix:@"dark"]) return HZAppearanceDark;
    if ([v hasPrefix:@"light"]) return HZAppearanceLight;
    return HZAppearanceSystem;
}

+ (void)setAppearance:(HZAppearance)appearance {
    [self setSetting:appearance == HZAppearanceDark ? @"dark" : appearance == HZAppearanceLight ? @"light" : @"system" for:@"appearance"];
    [self applyAppearanceToWindows];
    [NSNotificationCenter.defaultCenter postNotificationName:HZThemeChanged object:nil];
}

+ (float)glassStrength {
    NSString *v = [self settingFor:@"glass"];
    return v.length ? MAX(0, MIN(1, v.floatValue)) : 0.5f;
}

+ (void)setGlassStrength:(float)strength {
    [self setSetting:[NSString stringWithFormat:@"%.2f", MAX(0, MIN(1, strength))] for:@"glass"];
    [NSNotificationCenter.defaultCenter postNotificationName:HZThemeChanged object:nil];
}

+ (void)applyAppearanceToWindows {
    UIUserInterfaceStyle style = UIUserInterfaceStyleUnspecified;
    switch ([self appearance]) {
        case HZAppearanceDark: style = UIUserInterfaceStyleDark; break;
        case HZAppearanceLight: style = UIUserInterfaceStyleLight; break;
        default: break;
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            [UIView animateWithDuration:0.25 animations:^{ w.overrideUserInterfaceStyle = style; }];
        }
    }
    // This app has no scene manifest, so its window may not be in a scene's list yet.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in UIApplication.sharedApplication.windows) w.overrideUserInterfaceStyle = style;
#pragma clang diagnostic pop
}

@end
