#import "Launcher.h"
#import "Horizon-Swift.h"   // HZLauncherHost, the SwiftUI launcher (App/Swift)
#import "LauncherTheme.h"
#import "AccountClient.h"
#import "AccountStore.h"
#import <UIKit/UIKit.h>

@interface HZLauncherDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation HZLauncherDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    // The launcher is SwiftUI (App/Swift): three tabs in the system tab bar. The screens that are not rewritten yet
    // (Marketplace, Settings, Download, Files, Account) are still the UIKit ones, hosted inside it.
    self.window.rootViewController = [HZLauncherHost makeRoot];
    [self.window makeKeyAndVisible];
    // The saved System / Dark / Light choice, applied before the first frame is seen.
    [HZTheme applyAppearanceToWindows];
    self.window.overrideUserInterfaceStyle = [HZTheme appearance] == HZAppearanceDark ? UIUserInterfaceStyleDark
        : [HZTheme appearance] == HZAppearanceLight ? UIUserInterfaceStyleLight : UIUserInterfaceStyleUnspecified;
    // Once per run of the launcher: renews a saved sign-in in the background, so the game that starts next has a
    // Minecraft token that is not a day old (GameSession.h). Silent, and a network failure keeps the last answer.
    if ([[HZAccountStore shared] account]) [[HZAccountClient shared] recheck:^(BOOL reachable, BOOL owns, NSString *error) {}];
    return YES;
}
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return UIInterfaceOrientationMaskPortrait;
}
@end

int HorizonRunLauncher(int argc, char *argv[]) {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([HZLauncherDelegate class]));
}
