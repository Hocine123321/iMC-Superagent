// A short report of what this device and this installation allow, written before the engine
// starts. It exists to answer, on the owner's phone and without a computer, the questions that
// decide whether a Java runtime can run inside the app (docs/IOS_IMPLEMENTATION_ROADMAP.md, M8a).
// It changes nothing: it reads state and writes one text file.
#import <Foundation/Foundation.h>

// Writes <root>/diagnostics.txt (overwritten each launch) and returns the same text.
NSString *HorizonWriteDiagnostics(NSString *root);

// Small readings for the launcher's check-up (Diagnostics page). Each reads state and changes nothing.
// Bytes iOS will still let this app use before it ends it; 0 when the system reports no limit (the simulator).
unsigned long long HZDiagAvailableMemory(void);
// The app's memory footprint in bytes (the figure the system's memory limit is judged by).
unsigned long long HZDiagFootprint(void);
// One entitlement of this app: "absent", its value as text, or "(could not read)".
NSString *HZDiagEntitlement(NSString *name);
// The model identifier, for example iPhone13,2.
NSString *HZDiagMachine(void);
// The code-signing flags of this process (csops). *error is 0, or errno when the call failed.
unsigned int HZDiagCodeSigningFlags(int *error);
