// What is left of the Objective-C theme: the appearance choice (system, dark or light), the launcher.txt settings file
// that the Objective-C side shares with Swift, and the colour behind the window. The look of the launcher itself is
// SwiftUI (App/Swift: Palette.swift, Look.swift).
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HZAppearance) {
    HZAppearanceSystem = 0,
    HZAppearanceDark = 1,
    HZAppearanceLight = 2,
};

@interface HZTheme : NSObject
+ (UIColor *)background;     // the window behind the launcher and the game, before either has drawn

+ (HZAppearance)appearance;
+ (void)setAppearance:(HZAppearance)appearance;
+ (void)applyAppearanceToWindows;

// launcher.txt: one "key:value" per line. Reading and writing keeps every line the caller does not own.
+ (nullable NSString *)settingFor:(NSString *)key;
+ (void)setSetting:(NSString *)value for:(NSString *)key;   // in memory at once, on disk within about half a second
+ (void)flushSettings;     // write anything not yet written; call before reading or replacing the file another way
+ (void)forgetSettings;    // drop the memory copy (the file was deleted or replaced)

// How strongly the colour shows behind the launcher, 0 to 1 (the "glass:" line).
+ (float)glassStrength;
+ (void)setGlassStrength:(float)strength;
extern NSNotificationName const HZThemeChanged;
@end

NS_ASSUME_NONNULL_END
