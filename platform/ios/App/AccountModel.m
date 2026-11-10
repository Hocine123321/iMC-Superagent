#import "AccountModel.h"

NSString *const HZSignInNotConfigured =
    @"This build of iMC Horizon has no Microsoft sign-in yet, so it can't download the game. Use Game files to import a folder you prepared on your computer.";
NSString *const HZDoesNotOwn = @"This account doesn't own Minecraft: Java Edition.";
NSString *const HZNoProfile =
    @"This account has no Minecraft profile yet. Create one at minecraft.net, then sign in again.";
NSString *const HZSignInAgain = @"Your Microsoft sign-in expired. Sign in again.";
NSString *const HZAppNotApproved =
    @"The Minecraft services refused this app: its app is not approved by Mojang yet.";

NSString *HZMicrosoftClientID(void) {
    NSString *id_ = NSProcessInfo.processInfo.environment[@"HORIZON_MSA_CLIENT_ID"];
    if (!id_) id_ = NSBundle.mainBundle.infoDictionary[@"HZMicrosoftClientID"];
    if (![id_ isKindOfClass:NSString.class]) return nil;
    id_ = [id_ stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // An unfilled build setting arrives as its own name, "$(HZ_MSA_CLIENT_ID)": that is none.
    if (id_.length == 0 || [id_ hasPrefix:@"$("]) return nil;
    return id_;
}

static NSString *ReadLegacyTestClientID(void) {
    // Never baked into a build, so it cannot be shared by accident. Two places, the first wins:
    //  1. the environment variable HORIZON_MSA_LEGACY_CLIENT_ID (a desktop run, or a launcher that sets one);
    //  2. the file Documents/Horizon/test-client-id.txt, which the player puts there with the Files
    //     app (a LiveContainer launch cannot set environment variables). One line: the ID.
    NSString *id_ = NSProcessInfo.processInfo.environment[@"HORIZON_MSA_LEGACY_CLIENT_ID"];
    if (![id_ isKindOfClass:NSString.class] || id_.length == 0) {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *file = [[docs stringByAppendingPathComponent:@"Horizon"] stringByAppendingPathComponent:@"test-client-id.txt"];
        // Only a short file counts: an ID is 16 to 36 characters, so a stray large file is not read whole.
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:file error:nil];
        if (attrs && [attrs fileSize] > 0 && [attrs fileSize] <= 256) {
            id_ = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
        }
    }
    if (![id_ isKindOfClass:NSString.class]) return nil;
    id_ = [id_ stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // A client ID is letters, digits and dashes only. Anything else is not an ID, so it is not used.
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-"] invertedSet];
    if (id_.length < 8 || id_.length > 64 || [id_ rangeOfCharacterFromSet:bad].location != NSNotFound) return nil;
    return id_;
}

// Read once per run: the mode must not change under a sign-in that has started, and the file is
// not read again for every request. (Put the file there, then restart the app.)
NSString *HZLegacyTestClientID(void) {
    static NSString *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cached = ReadLegacyTestClientID(); });
    return cached;
}

BOOL HZSignInIsTestMode(void) { return HZMicrosoftClientID() == nil && HZLegacyTestClientID() != nil; }

NSString *HZActiveClientID(void) { return HZMicrosoftClientID() ?: HZLegacyTestClientID(); }

// The reply as a dictionary, or nil when it is not a JSON object.
static NSDictionary *Object(NSData *body) {
    if (body.length == 0) return nil;
    id v = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    return [v isKindOfClass:NSDictionary.class] ? v : nil;
}

static NSString *Str(NSDictionary *d, NSString *key) {
    id v = d[key];
    return [v isKindOfClass:NSString.class] && [v length] > 0 ? v : nil;
}

// JSON numbers arrive as NSNumber; the services also send some as strings. nil when neither.
static NSNumber *Num(NSDictionary *d, NSString *key) {
    id v = d[key];
    if ([v isKindOfClass:NSNumber.class]) return v;
    if ([v isKindOfClass:NSString.class]) {
        NSScanner *s = [NSScanner scannerWithString:v];
        long long n;
        if ([s scanLongLong:&n] && s.atEnd) return @(n);
    }
    return nil;
}

// The OAuth error codes as messages for the player (the desktop launcher's words).
static NSString *OAuthError(NSDictionary *v) {
    NSString *e = Str(v, @"error");
    if ([e isEqualToString:@"authorization_declined"]) return @"Sign-in was declined in the browser.";
    if ([e isEqualToString:@"expired_token"]) return @"The sign-in code expired. Start again.";
    if ([e isEqualToString:@"bad_verification_code"]) return @"The sign-in code was not recognised. Start again.";
    if ([e isEqualToString:@"invalid_grant"]) return HZSignInAgain;
    if ([e isEqualToString:@"invalid_client"] || [e isEqualToString:@"unauthorized_client"])
        return @"Microsoft refused this app's registration (client ID).";
    if (e) return [NSString stringWithFormat:@"Microsoft sign-in failed (%@).", e];
    return @"Microsoft sign-in failed.";
}

@implementation HZDeviceCode
+ (instancetype)parse:(NSData *)body error:(NSString **)error {
    NSDictionary *v = Object(body);
    NSString *user = Str(v, @"user_code"), *device = Str(v, @"device_code");
    if (!user || !device) {
        if (error) *error = v ? OAuthError(v) : @"Microsoft sign-in failed.";
        return nil;
    }
    HZDeviceCode *c = [HZDeviceCode new];
    c.userCode = user;
    c.deviceCode = device;
    c.verificationURI = Str(v, @"verification_uri") ?: @"https://www.microsoft.com/link";
    NSNumber *interval = Num(v, @"interval");
    c.interval = interval ? MAX(1, interval.doubleValue) : 5;   // never poll faster than once a second
    NSNumber *expires = Num(v, @"expires_in");
    c.expiresIn = expires ? expires.doubleValue : 900;
    return c;
}
@end

@implementation HZPollOutcome
+ (instancetype)parse:(NSData *)body status:(NSInteger)status {
    HZPollOutcome *o = [HZPollOutcome new];
    NSDictionary *v = Object(body);
    NSString *e = Str(v, @"error");
    if ([e isEqualToString:@"authorization_pending"]) { o.result = HZPollPending; return o; }
    if ([e isEqualToString:@"slow_down"]) { o.result = HZPollSlowDown; return o; }
    NSString *access = Str(v, @"access_token"), *refresh = Str(v, @"refresh_token");
    if (status == 200 && access && refresh) {
        o.result = HZPollSignedIn;
        o.accessToken = access;
        o.refreshToken = refresh;
        return o;
    }
    o.result = HZPollStopped;
    o.message = v ? OAuthError(v) : @"Microsoft sign-in failed.";
    return o;
}
@end

NSString *HZXstsMessage(long long xerr) {
    switch (xerr) {
        case 2148916233: return @"This Microsoft account has no Xbox profile yet. Sign in once at xbox.com to create one, then try again.";
        case 2148916235: return @"Xbox Live is not available in your country or region.";
        case 2148916236:
        case 2148916237: return @"This account needs adult verification on xbox.com before it can play.";
        case 2148916238: return @"This is a child account: an adult has to add it to a Microsoft family first.";
        default: return nil;
    }
}

@implementation HZXstsReply
+ (instancetype)parse:(NSData *)body status:(NSInteger)status {
    HZXstsReply *r = [HZXstsReply new];
    NSDictionary *v = Object(body);
    NSString *token = Str(v, @"Token");
    NSArray *xui = [v[@"DisplayClaims"] isKindOfClass:NSDictionary.class] ? v[@"DisplayClaims"][@"xui"] : nil;
    NSDictionary *first = [xui isKindOfClass:NSArray.class] && xui.count > 0 && [xui[0] isKindOfClass:NSDictionary.class] ? xui[0] : nil;
    NSString *uhs = Str(first, @"uhs");
    if (status == 200 && token && uhs) {
        r.token = token;
        r.userHash = uhs;
        return r;
    }
    NSNumber *xerr = Num(v, @"XErr");
    if (xerr) {
        r.message = HZXstsMessage(xerr.longLongValue) ?:
            [NSString stringWithFormat:@"Xbox Live refused the sign-in (error %lld).", xerr.longLongValue];
    } else {
        r.message = @"Xbox Live refused the sign-in.";
    }
    return r;
}
@end

NSString *HZMinecraftIdentityToken(NSString *userHash, NSString *xstsToken) {
    return [NSString stringWithFormat:@"XBL3.0 x=%@;%@", userHash, xstsToken];
}

BOOL HZOwnsJavaEdition(NSData *body) {
    NSArray *items = Object(body)[@"items"];
    if (![items isKindOfClass:NSArray.class]) return NO;
    for (id item in items) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSString *name = Str(item, @"name");
        if ([name isEqualToString:@"game_minecraft"] || [name isEqualToString:@"product_minecraft"]) return YES;
    }
    return NO;
}

@implementation HZProfile
+ (instancetype)parse:(NSData *)body status:(NSInteger)status message:(NSString **)message {
    if (status == 404) {
        if (message) *message = HZNoProfile;
        return nil;
    }
    NSDictionary *v = Object(body);
    NSString *name = Str(v, @"name"), *uuid = Str(v, @"id");
    if (status != 200 || !name || !uuid) {
        if (message) *message = @"Could not read this account's Minecraft profile.";
        return nil;
    }
    HZProfile *p = [HZProfile new];
    p.name = name;
    p.uuid = uuid;
    return p;
}
@end

@implementation HZAccountState
@end

BOOL HZMayDownload(BOOL signedIn, BOOL owns, BOOL reachable, BOOL freshAnswer) {
    if (!signedIn) return NO;
    if (reachable) return freshAnswer;   // the services' answer now, yes or no
    return owns;                         // offline: the last answer stands
}
