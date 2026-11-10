// The launcher's look: one place for colours, buttons and controls, so every screen follows the same
// rules and dark/light is one switch. Every colour is dynamic (it follows the window's appearance).
//
// There is no Liquid Glass here. The first pass drew surfaces and controls on UIGlassEffect and asked iOS 26 for
// its glass buttons; on the owner's phone (iOS 27.2) none of it read as glass, and over a near-black background
// it came out as flat black. Everything is now solid and has the same contrast in both themes.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HZAppearance) {
    HZAppearanceSystem = 0,
    HZAppearanceDark = 1,
    HZAppearanceLight = 2,
};

@interface HZTheme : NSObject
// Colours. All dynamic: they change with dark/light without a reload.
+ (UIColor *)background;     // the screen behind everything
+ (UIColor *)surface;        // a card or a plain button
+ (UIColor *)text;           // main text
+ (UIColor *)secondaryText;  // detail lines
+ (UIColor *)tertiaryText;   // small print
+ (UIColor *)accent;         // Horizon green, tuned for each mode
+ (UIColor *)onAccent;       // text on top of the accent
+ (UIColor *)danger;
+ (UIColor *)warning;
+ (UIColor *)separator;
+ (UIColor *)codeBackground; // behind logs and licence text

// The stored choice, and applying it to every window now.
+ (HZAppearance)appearance;
+ (void)setAppearance:(HZAppearance)appearance;
+ (void)applyAppearanceToWindows;
+ (NSString *)nameOfAppearance:(HZAppearance)appearance;

// launcher.txt: one "key:value" per line. These keep every line they do not own (openGame: belongs to
// LauncherModel and main.m). LauncherPrefs builds the named choices on top of them.
+ (nullable NSString *)settingFor:(NSString *)key;
+ (void)setSetting:(NSString *)value for:(NSString *)key;

// How strongly the colour shows behind the Home screen, 0...1 (default 0.5). Kept as "glass:" in launcher.txt (the
// name of the first version). Posts HZThemeChanged when set.
+ (float)glassStrength;
+ (void)setGlassStrength:(float)strength;
extern NSNotificationName const HZThemeChanged;

// A button. `prominent` is the accent-filled Play-style one (dark text on the light green, white on the dark
// green); the other is a quiet surface-coloured one. Both are solid, so contrast is the same everywhere.
+ (UIButton *)buttonWithTitle:(NSString *)title
                         symbol:(NSString *)symbolName
                      prominent:(BOOL)prominent
                         target:(id)target
                         action:(SEL)action;
// Same for a button that only shows a symbol (the "..." button).
+ (UIButton *)iconButtonWithSymbol:(NSString *)symbolName label:(NSString *)label;
// Changes the title of a button made by the two methods above.
+ (void)setTitle:(NSString *)title onButton:(UIButton *)button;

// Controls with the launcher's look (GlassControls.h): the stock UISlider, UISwitch and UISegmentedControl
// look plain, and only turn into Liquid Glass in an app built with the iOS 26 SDK, which CI does not have.
+ (UIControl *)glassSegmentedWithItems:(NSArray<NSString *> *)items selected:(NSInteger)selected;
+ (UIControl *)glassSliderMin:(float)min max:(float)max value:(float)value;
+ (UIControl *)glassSwitchOn:(BOOL)on;
+ (UIView *)glassProgressView;

// Standard text styles.
+ (UILabel *)labelWithSize:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;

// Dress a screen pushed on the navigation stack (background colour, bar).
+ (void)styleScreen:(UIViewController *)vc;
+ (void)styleNavigationBar:(UINavigationBar *)bar;
@end

NS_ASSUME_NONNULL_END
