#import "AccountStore.h"
#import "LauncherModel.h"
#import <Security/Security.h>

static NSString *const kService = @"dev.imc.horizon.account";
static NSString *const kRefresh = @"microsoft-refresh";
static NSString *const kMinecraft = @"minecraft-access";

static NSDictionary *Query(NSString *account) {
    return @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService: kService,
              (__bridge id)kSecAttrAccount: account };
}

// Replaces the item. Delete then add, so an item left by an older run with a different
// accessibility class cannot keep the old one.
static BOOL Put(NSString *account, NSString *secret) {
    SecItemDelete((__bridge CFDictionaryRef)Query(account));
    NSMutableDictionary *add = [Query(account) mutableCopy];
    add[(__bridge id)kSecValueData] = [secret dataUsingEncoding:NSUTF8StringEncoding];
    add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    return SecItemAdd((__bridge CFDictionaryRef)add, NULL) == errSecSuccess;
}

static NSString *Get(NSString *account) {
    NSMutableDictionary *q = [Query(account) mutableCopy];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef out = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &out) != errSecSuccess || !out) return nil;
    NSData *data = CFBridgingRelease(out);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@implementation HZAccountStore

+ (instancetype)shared {
    static HZAccountStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [HZAccountStore new]; });
    return s;
}

- (NSString *)path { return [[HZLauncherModel shared].root stringByAppendingPathComponent:@"account.txt"]; }

// account.txt: name, uuid and owns, one "key=value" per line (the same shape as launcher.txt).
- (HZAccountState *)account {
    NSString *text = [NSString stringWithContentsOfFile:self.path encoding:NSUTF8StringEncoding error:nil];
    if (!text) return nil;
    HZAccountState *a = [HZAccountState new];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSRange eq = [line rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString *key = [line substringToIndex:eq.location], *value = [line substringFromIndex:eq.location + 1];
        if ([key isEqualToString:@"name"]) a.name = value;
        else if ([key isEqualToString:@"uuid"]) a.uuid = value;
        else if ([key isEqualToString:@"owns"]) a.owns = [value isEqualToString:@"1"];
    }
    return a.name.length && a.uuid.length ? a : nil;   // half an account is no account
}

// A profile name is 3 to 16 letters, digits and underscores and a UUID is hex, so nothing real
// holds a newline or "="; a reply that did would split the file's lines, so it is refused.
static BOOL PlainValue(NSString *v) {
    return v.length > 0 && v.length <= 64 &&
           [v rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\n\r="]].location == NSNotFound;
}

- (BOOL)writeAccount:(HZAccountState *)a {
    if (!PlainValue(a.name) || !PlainValue(a.uuid)) return NO;
    NSString *text = [NSString stringWithFormat:@"name=%@\nuuid=%@\nowns=%@\n", a.name, a.uuid, a.owns ? @"1" : @"0"];
    return [text writeToFile:self.path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (BOOL)saveAccount:(HZAccountState *)account refreshToken:(NSString *)refresh minecraftToken:(NSString *)minecraft {
    // The secrets first: an account file with no secrets behind it would say "signed in" for nothing.
    if (!Put(kRefresh, refresh) || !Put(kMinecraft, minecraft)) {
        SecItemDelete((__bridge CFDictionaryRef)Query(kRefresh));
        SecItemDelete((__bridge CFDictionaryRef)Query(kMinecraft));
        return NO;
    }
    return [self writeAccount:account];
}

- (void)saveOwns:(BOOL)owns {
    HZAccountState *a = [self account];
    if (!a) return;
    a.owns = owns;
    [self writeAccount:a];
}

- (NSString *)refreshToken { return Get(kRefresh); }
- (NSString *)minecraftToken { return Get(kMinecraft); }

- (void)signOut {
    SecItemDelete((__bridge CFDictionaryRef)Query(kRefresh));
    SecItemDelete((__bridge CFDictionaryRef)Query(kMinecraft));
    [NSFileManager.defaultManager removeItemAtPath:self.path error:nil];
}

@end
