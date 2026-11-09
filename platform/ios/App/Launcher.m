#import "Launcher.h"
#import "LauncherHome.h"
#import <UIKit/UIKit.h>

@interface HZLauncherDelegate : UIResponder <UIApplicationDelegate, UINavigationControllerDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation HZLauncherDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[HZLauncherHomeController new]];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    nav.navigationBar.tintColor = [UIColor colorWithRed:0.36 green:0.74 blue:0.33 alpha:1];
    // The home screen has its own title; the bar appears only on the screens pushed over it.
    nav.delegate = self;
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}
- (void)navigationController:(UINavigationController *)nav willShowViewController:(UIViewController *)vc animated:(BOOL)animated {
    [nav setNavigationBarHidden:[vc isKindOfClass:[HZLauncherHomeController class]] animated:animated];
}
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return UIInterfaceOrientationMaskLandscape;
}
@end

int HorizonRunLauncher(int argc, char *argv[]) {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([HZLauncherDelegate class]));
}
