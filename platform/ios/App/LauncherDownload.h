// The Download screen (M8b, step 2): downloads Minecraft 26.3 from Mojang to the phone with a
// progress bar, after the sign-in gate (HZMayDownload) says yes. Preparing the files for the game
// (M8b step 3, the Java part) is not here and is not built; this only puts Mojang's files on disk.
//
// Developer override: a file named `developer-download` in the Horizon folder skips the sign-in gate
// so the downloader can be tried before Mojang approves the app's sign-in. It is for the owner's own
// phone; the screen says plainly when it is on.
#import <UIKit/UIKit.h>

@interface HZLauncherDownloadController : UIViewController
@end
