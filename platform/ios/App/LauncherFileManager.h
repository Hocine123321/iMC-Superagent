// The in-app file manager (M13): browse, share, rename, delete, make folders and add files inside the
// app's Horizon folder (the one the Files app shows), and nowhere else. The rules live in FileBrowser.
#import <UIKit/UIKit.h>

@interface HZLauncherFileManagerController : UITableViewController
// Opens at `relativePath` inside the Horizon folder ("" is the folder itself).
- (instancetype)initWithPath:(NSString *)relativePath;
@end
