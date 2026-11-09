// The session log: a timeline of how the phone is doing while the app runs, for M6 (benchmark
// baseline) and M7 (memory and heat tuning). One line every 5 seconds in
// Documents/Horizon/session-log.csv, written off the main thread.
//
// It stays on the phone. Nothing here sends anything anywhere; the launcher's Share button hands
// the file to the person, who decides what to do with it.
//
// What a row holds: seconds since the app started, the app's memory footprint and what iOS says
// it may still use (the two numbers the jetsam limit is judged by), the thermal state, Low Power
// Mode, the battery level and whether it is charging, and whether the app is in the foreground.
// The engine's own frame times are not here: they need the engine, and `horizon/` is not touched.
#import <Foundation/Foundation.h>

// Call once, early in main(). `root` is Documents/Horizon. Starts a new log (the last one is kept
// as session-log-previous.csv) and the sampling timer. Safe to call from the launcher path too.
void HorizonStartSessionLog(NSString *root);

// One sample's text, as a CSV line without the newline. Pure formatting, split out so the format
// is stable and testable: see SessionLog.m for the column list.
NSString *HorizonSessionLogLine(double seconds, unsigned long long footprintMB,
                                unsigned long long availableMB, NSInteger thermal,
                                BOOL lowPower, float battery, NSInteger batteryState,
                                BOOL foreground);
