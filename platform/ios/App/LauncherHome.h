// The launcher's home screen: the state of the game files, Play, and the way to the other
// screens. Pure UIKit, no storyboard. The app is a launcher first: this is what opens, and the game
// starts on the next launch after Play (winit's EventLoop cannot run after UIApplicationMain, so
// the launcher and the game are two runs of the app; see docs/IOS_IMPLEMENTATION_ROADMAP.md, M3b).
#import <UIKit/UIKit.h>

@interface HZLauncherHomeController : UIViewController
@end
