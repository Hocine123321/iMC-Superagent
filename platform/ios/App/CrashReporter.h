// Records why the app ended, into <root>/crash.txt, because the engine's own crash report only
// covers a Rust panic on the main thread. A native abort (Metal, an Objective-C exception, a
// failed assertion, a bad memory access) leaves nothing else behind.
//
//  - Fatal signals (SEGV, BUS, ILL, ABRT, TRAP, FPE, SYS): the signal, the fault address, the
//    thread and a backtrace, written with write(2) to a descriptor opened at install time.
//  - Uncaught Objective-C exceptions: name, reason and call stack.
//  - A "running" marker, removed when the app goes to the background. If it is still there at the
//    next launch the last run ended with no signal and no exception: the system killed it
//    (usually memory), and the report says so with the last memory figures it saw.
#import <Foundation/Foundation.h>

// Call first thing in main(), before the engine starts. `root` is Documents/Horizon.
void HorizonInstallCrashReporter(NSString *root);

// Call before a deliberate exit(): removes the "running" marker, so the next launch does not take
// it for a kill by the system.
void HorizonCrashReporterCleanExit(void);

// Engine-side breadcrumb: the last step reached, shown in the report. Cheap and signal-safe to
// read; call from anywhere (also exported to Rust as horizon_ios_breadcrumb).
void horizon_ios_breadcrumb(const char *step);
