#import "Diagnostics.h"
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <errno.h>
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

NSString *HorizonWriteDiagnostics(NSString *root) {
    NSMutableString *r = [NSMutableString string];
    NSString *file = [root stringByAppendingPathComponent:@"diagnostics.txt"];
    void (^flush)(void) = ^{ [r writeToFile:file atomically:NO encoding:NSUTF8StringEncoding error:nil]; };
    void (^line)(NSString *) = ^(NSString *s) { [r appendFormat:@"%@\n", s]; flush(); };

    UIDevice *d = UIDevice.currentDevice;
    NSString *m = DeviceModel();
    line(@"Horizon diagnostics (read-only checks; nothing is changed)");
    line([NSString stringWithFormat:@"date: %@", [NSDate date]]);
    line([NSString stringWithFormat:@"iOS: %@  model: %@  %@", d.systemVersion, m, ChipNote(m)]);
    line([NSString stringWithFormat:@"physical memory: %.2f GB", NSProcessInfo.processInfo.physicalMemory / 1073741824.0]);

    line(@"");
    line(@"-- signing and entitlements of THIS app --");
    line([NSString stringWithFormat:@"get-task-allow: %@   (needed for StikDebug to list the app)", Entitlement(@"get-task-allow")]);
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

    // Last, because a refusal by the kernel kills the process; the lines above are already on disk.
    if (cs & CS_DEBUGGED) {
        line(@"");
        line(@"-- JIT page test (runs only when CS_DEBUGGED is set) --");
        line(@"four ways to get executable memory, each tried alone (a line is written before each):");
        line(@"trying A: mmap(MAP_JIT, RWX) ..."); line(ProbeA());
        line(@"trying B: mmap(RWX) without MAP_JIT ..."); line(ProbeB());
        line(@"trying C: mmap(RW), write, mprotect(RX) ..."); line(ProbeC());
        line(@"trying D: mmap(MAP_JIT, RW), write, mprotect(RX) ..."); line(ProbeD());
    } else {
        line(@"");
        line(@"-- JIT page test skipped: it would be killed without a debugger attached --");
    }
    line(@"");
    line(@"end of report");
    return r;
}
