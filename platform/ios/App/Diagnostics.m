#import "Diagnostics.h"
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>
#include <unistd.h>
#include <libkern/OSCacheControl.h>

// csops(2) is not in the public headers; it is the call every JIT-aware iOS app uses to read the
// code-signing flags of a process. CS_DEBUGGED is set once a debugger has attached and allowed JIT.
extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
#define CS_OPS_STATUS 0
#define CS_VALID 0x00000001
#define CS_DEBUGGED 0x10000000
#define CS_HARD 0x00000100
#define CS_KILL 0x00000200
#define CS_RUNTIME 0x00010000
#define CS_PLATFORM_BINARY 0x04000000

// SecTask is private API on iOS, but reading one's own entitlement is what the StikJIT
// integration guide itself shows for the get-task-allow check.
typedef const void *HzSecTaskRef;
extern HzSecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(HzSecTaskRef task, CFStringRef entitlement, CFErrorRef *error);

static NSString *Entitlement(NSString *name) {
    HzSecTaskRef t = SecTaskCreateFromSelf(NULL);
    if (!t) return @"(could not read)";
    CFTypeRef v = SecTaskCopyValueForEntitlement(t, (__bridge CFStringRef)name, NULL);
    CFRelease(t);
    if (!v) return @"absent";
    NSString *s = [NSString stringWithFormat:@"%@", (__bridge id)v];
    CFRelease(v);
    return s;
}

static NSString *DeviceModel(void) {
    struct utsname u; uname(&u);
    return [NSString stringWithUTF8String:u.machine];
}

// Maps the model identifier to a chip only where I am sure. iPhone13,2 is the iPhone 12 (A14).
static NSString *ChipNote(NSString *m) {
    if ([m isEqualToString:@"iPhone13,1"] || [m isEqualToString:@"iPhone13,2"] ||
        [m isEqualToString:@"iPhone13,3"] || [m isEqualToString:@"iPhone13,4"])
        return @"A14 (iPhone 12 family): no TXM";
    return @"(chip not mapped here)";
}

// JIT probes. Four ways to get executable memory, each tried alone and reported alone. The
// first run used only the first way and was refused (errno 1); that does not show the others are
// refused, so each is tried. A kill by the kernel cannot be caught: the caller writes a line
// naming the probe BEFORE it runs, so a crash still leaves the earlier lines in the file.
static const uint32_t kCode[2] = { 0x52800540, 0xD65F03C0 };  // arm64: mov w0, #42 ; ret

static NSString *RunPage(void *p, size_t len, const char *how) {
    memcpy(p, kCode, sizeof kCode);
    sys_icache_invalidate(p, sizeof kCode);
    int r = ((int (*)(void))p)();
    munmap(p, len);
    return [NSString stringWithFormat:@"%s: executed, returned %d (expected 42) -> %@", how, r, r == 42 ? @"WORKS" : @"unexpected"];
}

// A. one call: MAP_JIT, read+write+exec.
static NSString *ProbeA(void) {
    size_t len = 16384;
    void *p = mmap(NULL, len, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (p == MAP_FAILED) return [NSString stringWithFormat:@"A mmap(MAP_JIT, RWX): refused, errno %d (%s)", errno, strerror(errno)];
    return RunPage(p, len, "A mmap(MAP_JIT, RWX)");
}

// B. plain RWX, no MAP_JIT.
static NSString *ProbeB(void) {
    size_t len = 16384;
    void *p = mmap(NULL, len, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (p == MAP_FAILED) return [NSString stringWithFormat:@"B mmap(RWX, no MAP_JIT): refused, errno %d (%s)", errno, strerror(errno)];
    return RunPage(p, len, "B mmap(RWX, no MAP_JIT)");
}

// C. map read+write, fill it, then mprotect to read+exec (the usual debugger-attached route).
static NSString *ProbeC(void) {
    size_t len = 16384;
    void *p = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (p == MAP_FAILED) return [NSString stringWithFormat:@"C mmap(RW): refused, errno %d (%s)", errno, strerror(errno)];
    memcpy(p, kCode, sizeof kCode);
    if (mprotect(p, len, PROT_READ | PROT_EXEC) != 0)
        return [NSString stringWithFormat:@"C mmap(RW) then mprotect(RX): mprotect refused, errno %d (%s)", errno, strerror(errno)];
    sys_icache_invalidate(p, sizeof kCode);
    int r = ((int (*)(void))p)();
    munmap(p, len);
    return [NSString stringWithFormat:@"C mmap(RW) then mprotect(RX): executed, returned %d (expected 42) -> %@", r, r == 42 ? @"WORKS" : @"unexpected"];
}

// D. MAP_JIT with read+write only, then mprotect to read+exec.
static NSString *ProbeD(void) {
    size_t len = 16384;
    void *p = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (p == MAP_FAILED) return [NSString stringWithFormat:@"D mmap(MAP_JIT, RW): refused, errno %d (%s)", errno, strerror(errno)];
    memcpy(p, kCode, sizeof kCode);
    if (mprotect(p, len, PROT_READ | PROT_EXEC) != 0)
        return [NSString stringWithFormat:@"D mmap(MAP_JIT, RW) then mprotect(RX): mprotect refused, errno %d (%s)", errno, strerror(errno)];
    sys_icache_invalidate(p, sizeof kCode);
    int r = ((int (*)(void))p)();
    munmap(p, len);
    return [NSString stringWithFormat:@"D mmap(MAP_JIT, RW) then mprotect(RX): executed, returned %d (expected 42) -> %@", r, r == 42 ? @"WORKS" : @"unexpected"];
}

static NSString *Exists(NSString *path) {
    BOOL dir = NO;
    BOOL e = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dir];
    return e ? (dir ? @"folder present" : @"file present") : @"not found";
}

// Appends one line and forces it to disk before returning, so a kernel kill on the next
// instruction cannot lose it. The log is never rewritten: each launch adds a section.
static void DurableAppend(NSString *path, NSString *text) {
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    NSData *d = [text dataUsingEncoding:NSUTF8StringEncoding];
    write(fd, d.bytes, d.length);
    fcntl(fd, F_FULLFSYNC);
    close(fd);
}

NSString *HorizonWriteDiagnostics(NSString *root) {
    NSMutableString *r = [NSMutableString string];
    NSString *file = [root stringByAppendingPathComponent:@"diagnostics.txt"];
    NSString *stateFile = [root stringByAppendingPathComponent:@"probe-state.txt"];
    void (^line)(NSString *) = ^(NSString *s) { [r appendFormat:@"%@\n", s]; DurableAppend(file, [s stringByAppendingString:@"\n"]); };

    UIDevice *d = UIDevice.currentDevice;
    NSString *m = DeviceModel();
    line(@"Horizon diagnostics (read-only checks; nothing is changed)");
    line([NSString stringWithFormat:@"date: %@", [NSDate date]]);
    line([NSString stringWithFormat:@"iOS: %@  model: %@  %@", d.systemVersion, m, ChipNote(m)]);
    line([NSString stringWithFormat:@"physical memory: %.2f GB", NSProcessInfo.processInfo.physicalMemory / 1073741824.0]);

    line(@"");
    line(@"-- signing and entitlements of THIS app --");
    line([NSString stringWithFormat:@"get-task-allow: %@   (needed for StikDebug to list the app)", Entitlement(@"get-task-allow")]);
    line([NSString stringWithFormat:@"com.apple.developer.cs.allow-jit: %@   (asked for by this build; absent means the signing tool removed it)", Entitlement(@"com.apple.developer.cs.allow-jit")]);
    line([NSString stringWithFormat:@"dynamic-codesigning: %@", Entitlement(@"dynamic-codesigning")]);
    line([NSString stringWithFormat:@"com.apple.developer.kernel.increased-memory-limit: %@", Entitlement(@"com.apple.developer.kernel.increased-memory-limit")]);
    line([NSString stringWithFormat:@"com.apple.developer.kernel.extended-virtual-addressing: %@", Entitlement(@"com.apple.developer.kernel.extended-virtual-addressing")]);

    uint32_t cs = 0;
    int rc = csops(getpid(), CS_OPS_STATUS, &cs, sizeof cs);
    line(@"");
    line(@"-- code-signing status of this process (csops) --");
    if (rc == 0) {
        line([NSString stringWithFormat:@"flags: 0x%08x   CS_VALID=%d  CS_DEBUGGED=%d  CS_RUNTIME=%d",
              cs, !!(cs & CS_VALID), !!(cs & CS_DEBUGGED), !!(cs & CS_RUNTIME)]);
        line((cs & CS_DEBUGGED) ? @"CS_DEBUGGED is SET: a debugger has attached, JIT is allowed."
                               : @"CS_DEBUGGED is NOT set: no debugger attached yet. Enable JIT for this app in StikDebug, then relaunch or tap again.");
    } else {
        line([NSString stringWithFormat:@"csops failed: errno %d", errno]);
    }

    line(@"");
    line(@"-- Java runtime (nothing is loaded; only looked for) --");
    NSString *jre = [root stringByAppendingPathComponent:@"jre25"];
    line([NSString stringWithFormat:@"%@/jre25: %@", root.lastPathComponent, Exists(jre)]);
    line([NSString stringWithFormat:@"jre25/lib/server/libjvm.dylib: %@", Exists([jre stringByAppendingPathComponent:@"lib/server/libjvm.dylib"])]);
    line([NSString stringWithFormat:@"jre25/lib/libjli.dylib: %@", Exists([jre stringByAppendingPathComponent:@"lib/libjli.dylib"])]);
    line([NSString stringWithFormat:@"jre25/release: %@", Exists([jre stringByAppendingPathComponent:@"release"])]);

    // One probe per launch. A kernel kill cannot be caught, so the state file says which probe
    // is about to run (synced to disk first). If the next launch finds a probe marked started but
    // not finished, that probe killed the app: it is recorded as KILLED and the next one is tried.
    line(@"");
    line(@"-- executable-memory probes (one per launch, results kept across kills) --");
    NSArray<NSString *> *names = @[@"A mmap(MAP_JIT, RWX)", @"B mmap(RWX) no MAP_JIT",
                                   @"C mmap(RW) write mprotect(RX)", @"D mmap(MAP_JIT, RW) write mprotect(RX)"];
    NSString *(*fns[4])(void) = { ProbeA, ProbeB, ProbeC, ProbeD };
    NSString *state = [NSString stringWithContentsOfFile:stateFile encoding:NSUTF8StringEncoding error:nil] ?: @"";
    // state lines: "start N" then "done N" ; the highest N with start but no done was killed.
    int next = 0;
    for (int i = 0; i < 4; i++) {
        BOOL started = [state containsString:[NSString stringWithFormat:@"start %d\n", i]];
        BOOL done = [state containsString:[NSString stringWithFormat:@"done %d\n", i]];
        if (started && !done) { line([NSString stringWithFormat:@"probe %@: KILLED the app (started, never finished)", names[i]]);
            DurableAppend(stateFile, [NSString stringWithFormat:@"done %d\n", i]); }
        if (started || done) next = i + 1;
    }
    // The executable-memory probes are finished (all four failed on the iPhone 12, iOS 27.2) and
    // two of them kill the app, so they no longer run on their own. Create an empty file named
    // run-probes.txt in this folder to run them again.
    // probes-ad.txt: run only the two MAP_JIT probes, A then D (one per launch). B and C kill the app and already
    // gave their answer. Its own state keys (startAD / doneAD), so the state file of the earlier four-probe run
    // does not matter.
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL onlyMapJit = [fm fileExistsAtPath:[root stringByAppendingPathComponent:@"probes-ad.txt"]];
    if (onlyMapJit) {
        for (int i = 0; i < 4; i += 3) {
            NSString *sk = [NSString stringWithFormat:@"startAD %d\n", i], *dk = [NSString stringWithFormat:@"doneAD %d\n", i];
            if ([state containsString:sk] && ![state containsString:dk]) {
                line([NSString stringWithFormat:@"probe %@: KILLED the app (started, never finished)", names[i]]);
                DurableAppend(stateFile, dk);
                state = [state stringByAppendingString:dk];
            }
        }
        int pick = -1;
        for (int i = 0; i < 4; i += 3) {
            if (![state containsString:[NSString stringWithFormat:@"startAD %d\n", i]]) { pick = i; break; }
        }
        if (!(cs & CS_DEBUGGED)) {
            line(@"CS_DEBUGGED is not set: probes skipped (they would be killed). Enable JIT in StikDebug and relaunch.");
        } else if (pick < 0) {
            line(@"A and D have both been tried; delete probe-state.txt in this folder to run them again.");
        } else {
            line([NSString stringWithFormat:@"running probe %@ now (launch the app again afterwards for the next one)", names[pick]]);
            DurableAppend(stateFile, [NSString stringWithFormat:@"startAD %d\n", pick]);
            line([NSString stringWithFormat:@"probe result: %@", fns[pick]()]);
            DurableAppend(stateFile, [NSString stringWithFormat:@"doneAD %d\n", pick]);
        }
    } else {
        NSString *marker = [root stringByAppendingPathComponent:@"run-probes.txt"];
        if (![fm fileExistsAtPath:marker]) {
            line(@"probes are switched off (create run-probes.txt, or probes-ad.txt for only A and D, in this folder).");
        } else if (!(cs & CS_DEBUGGED)) {
            line(@"CS_DEBUGGED is not set: probes skipped (they would be killed). Enable JIT in StikDebug and relaunch.");
        } else if (next >= 4) {
            line(@"all four probes have been tried; delete probe-state.txt in this folder to run them again.");
        } else {
            line([NSString stringWithFormat:@"running probe %@ now (launch the app again afterwards for the next one)", names[next]]);
            DurableAppend(stateFile, [NSString stringWithFormat:@"start %d\n", next]);
            NSString *res = fns[next]();
            line([NSString stringWithFormat:@"probe result: %@", res]);
            DurableAppend(stateFile, [NSString stringWithFormat:@"done %d\n", next]);
        }
    }
    line(@"");
    line(@"end of report");
    return r;
}
