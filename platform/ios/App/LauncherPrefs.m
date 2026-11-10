#import "LauncherPrefs.h"
#import "LauncherTheme.h"

@implementation HZPrefs

+ (BOOL)boolFromText:(NSString *)text fallback:(BOOL)fallback {
    NSString *t = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    if ([t isEqualToString:@"true"]) return YES;
    if ([t isEqualToString:@"false"]) return NO;
    return fallback;
}
+ (BOOL)get:(NSString *)key fallback:(BOOL)fallback { return [self boolFromText:[HZTheme settingFor:key] fallback:fallback]; }
+ (void)set:(BOOL)on key:(NSString *)key {
    [HZTheme setSetting:on ? @"true" : @"false" for:key];
    [NSNotificationCenter.defaultCenter postNotificationName:HZThemeChanged object:nil];
}

+ (BOOL)showMods { return [self get:@"market.mods" fallback:NO]; }
+ (BOOL)showShaders { return [self get:@"market.shaders" fallback:NO]; }
+ (BOOL)showOtherKinds { return [self get:@"market.other" fallback:NO]; }
+ (BOOL)useModrinth { return [self get:@"market.modrinth" fallback:NO]; }
+ (void)setShowMods:(BOOL)on { [self set:on key:@"market.mods"]; }
+ (void)setShowShaders:(BOOL)on { [self set:on key:@"market.shaders"]; }
+ (void)setShowOtherKinds:(BOOL)on { [self set:on key:@"market.other"]; }
+ (void)setUseModrinth:(BOOL)on { [self set:on key:@"market.modrinth"]; }

+ (BOOL)confirmInstalls { return [self get:@"confirmInstalls" fallback:YES]; }
+ (BOOL)compactLists { return [self get:@"compact" fallback:NO]; }
+ (BOOL)reduceMotion { return [self get:@"reduceMotion" fallback:NO]; }
+ (void)setConfirmInstalls:(BOOL)on { [self set:on key:@"confirmInstalls"]; }
+ (void)setCompactLists:(BOOL)on { [self set:on key:@"compact"]; }
+ (void)setReduceMotion:(BOOL)on { [self set:on key:@"reduceMotion"]; }

+ (BOOL)isKindVisible:(NSString *)kind {
    if ([kind isEqualToString:@"resourcepack"]) return YES;
    if ([kind isEqualToString:@"mod"]) return [self showMods];
    if ([kind isEqualToString:@"shader"]) return [self showShaders];
    return [self showOtherKinds];
}
@end
