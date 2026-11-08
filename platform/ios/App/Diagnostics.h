// A short report of what this device and this installation allow, written before the engine
// starts. It exists to answer, on the owner's phone and without a computer, the questions that
// decide whether a Java runtime can run inside the app (docs/IOS_IMPLEMENTATION_ROADMAP.md, M8a).
// It changes nothing: it reads state and writes one text file.
#import <Foundation/Foundation.h>

// Writes <root>/diagnostics.txt (overwritten each launch) and returns the same text.
NSString *HorizonWriteDiagnostics(NSString *root);
