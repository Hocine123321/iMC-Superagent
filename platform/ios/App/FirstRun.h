// The screen shown when the prepared game files are not on the phone yet.
//
// The engine has its own screen for this, but it was written for the desktop launcher ("download
// the launcher", "run horizon-prepare") and tries to open a web page with programs iOS does not
// have. On a phone the player has to copy a folder in with the Files app, so the app says exactly
// that, with the real folder name.
//
// winit's EventLoop refuses to run after UIApplicationMain has been called, so this is a whole
// small app of its own, used instead of the engine, never before it. Copying the files and opening
// the app again is the way on from here.
#import <Foundation/Foundation.h>

// Does not return: runs UIApplicationMain with a single instruction screen.
// `resources` is the folder the engine reads (Documents/Horizon/resources).
int HorizonRunFirstRunScreen(int argc, char *argv[], NSString *resources);

// Whether the prepared files are there: the same first test the engine makes
// (`missing_resources` in loading_screen.rs: a horizon-resources.json file).
BOOL HorizonResourcesPresent(NSString *resources);
