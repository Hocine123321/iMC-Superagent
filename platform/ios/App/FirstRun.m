#import "FirstRun.h"
#import <UIKit/UIKit.h>

static NSString *gResources;

BOOL HorizonResourcesPresent(NSString *resources) {
    BOOL isDir = NO;
    NSString *manifest = [resources stringByAppendingPathComponent:@"horizon-resources.json"];
    return [[NSFileManager defaultManager] fileExistsAtPath:manifest isDirectory:&isDir] && !isDir;
}

@interface HZFirstRunController : UIViewController
@end

@implementation HZFirstRunController
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    UILabel *title = [UILabel new];
    title.text = @"iMC Horizon needs your game files";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
    title.textAlignment = NSTextAlignmentCenter;

    UILabel *steps = [UILabel new];
    steps.numberOfLines = 0;
    steps.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    steps.font = [UIFont systemFontOfSize:16];
    steps.text =
        @"1.  On your computer, open the Horizon launcher, pick 26.3 and press Play once.\n"
        @"2.  Copy the CONTENTS of the folder  .local/horizon-client/26.3  (about 500 MB). "
        @"horizon-resources.json must be directly inside it.\n"
        @"3.  On this iPhone open Files > On My iPhone > Horizon > Horizon > resources and put "
        @"them there, so that  resources/horizon-resources.json  exists.\n"
        @"4.  Close iMC Horizon completely and open it again.";

    UILabel *found = [UILabel new];
    found.numberOfLines = 0;
    found.textAlignment = NSTextAlignmentCenter;
    found.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    found.textColor = [UIColor colorWithRed:1 green:0.75 blue:0.35 alpha:1];
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:gResources error:nil];
    found.text = [NSString stringWithFormat:@"Looking for:  %@/horizon-resources.json\n%@",
                  @"Files > On My iPhone > Horizon > Horizon > resources",
                  items.count ? [NSString stringWithFormat:@"The folder has %lu item(s) but no horizon-resources.json. "
                                "Copied the folder itself instead of its contents?", (unsigned long)items.count]
                              : @"The folder is empty."];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, steps, found]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:40],
        [stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-40],
    ]];
}
@end

@interface HZFirstRunDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation HZFirstRunDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [HZFirstRunController new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int HorizonRunFirstRunScreen(int argc, char *argv[], NSString *resources) {
    gResources = resources;
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([HZFirstRunDelegate class]));
}
