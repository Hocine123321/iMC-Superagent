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

+ (NSString *)settingFor:(NSString *)key {
    NSString *text = [NSString stringWithContentsOfFile:[self settingsPath] encoding:NSUTF8StringEncoding error:nil];
    NSString *prefix = [key stringByAppendingString:@":"];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) if ([line hasPrefix:prefix]) return [line substringFromIndex:prefix.length];
    return nil;
}

+ (void)setSetting:(NSString *)value for:(NSString *)key {
    NSString *old = [NSString stringWithContentsOfFile:[self settingsPath] encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSString *prefix = [key stringByAppendingString:@":"];
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *line in [old componentsSeparatedByString:@"\n"]) if (line.length && ![line hasPrefix:prefix]) [kept addObject:line];
    [kept addObject:[prefix stringByAppendingString:value]];
    [[NSFileManager defaultManager] createDirectoryAtPath:[HZLauncherModel shared].root withIntermediateDirectories:YES attributes:nil error:nil];
    [[[kept componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] writeToFile:[self settingsPath] atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
