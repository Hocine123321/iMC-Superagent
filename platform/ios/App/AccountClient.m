#import "AccountClient.h"
#import "AccountStore.h"

// The services, as in horizon/docs/microsoft-account.md.
static NSString *const kMicrosoft = @"https://login.microsoftonline.com/consumers/oauth2/v2.0";
static NSString *const kXboxUser = @"https://user.auth.xboxlive.com/user/authenticate";
static NSString *const kXsts = @"https://xsts.auth.xboxlive.com/xsts/authorize";
static NSString *const kMinecraft = @"https://api.minecraftservices.com";
static NSString *const kScope = @"XboxLive.signin offline_access";
// Test mode only (HZSignInIsTestMode): the legacy live.com endpoints a legacy app ID needs.
static NSString *const kLiveDeviceCode = @"https://login.live.com/oauth20_connect.srf";
static NSString *const kLiveToken = @"https://login.live.com/oauth20_token.srf";
static NSString *const kLegacyScope = @"service::user.auth.xboxlive.com::MBI_SSL";

static NSString *DeviceCodeURL(void) { return HZSignInIsTestMode() ? kLiveDeviceCode : [kMicrosoft stringByAppendingString:@"/devicecode"]; }
static NSString *TokenURL(void) { return HZSignInIsTestMode() ? kLiveToken : [kMicrosoft stringByAppendingString:@"/token"]; }
static NSString *ScopeForRequests(void) { return HZSignInIsTestMode() ? kLegacyScope : kScope; }
// The ticket Xbox Live wants: v2 tokens carry "d=" in front, the legacy ones go bare.
static NSString *RpsTicket(NSString *msAccess) { return HZSignInIsTestMode() ? msAccess : [@"d=" stringByAppendingString:msAccess]; }

// One answer. `reached` is NO for a request that went nowhere (no network, a timeout), as against
// one that got an answer of any status. (A class, not a struct: ARC does not allow objects in one.)
@interface Reply : NSObject
@property (strong) NSData *body;
@property NSInteger status;
@property BOOL reached;
@end
@implementation Reply
@end

@interface HZAccountClient ()
@property (strong) NSURLSession *session;
@property (atomic) BOOL cancelled;
@end

@implementation HZAccountClient

+ (instancetype)shared {
    static HZAccountClient *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [HZAccountClient new]; });
    return c;
}

- (instancetype)init {
    if ((self = [super init])) {
        // Ephemeral: no cookies, no cache, nothing on disk. A token cannot end up in a URL cache.
        NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        cfg.timeoutIntervalForRequest = 20;
        cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        cfg.HTTPCookieStorage = nil;
        cfg.URLCredentialStorage = nil;
        self.session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

// One request, waited for. Always called off the main thread (it blocks on a semaphore).
- (Reply *)send:(NSString *)method url:(NSString *)url form:(NSDictionary *)form json:(id)json bearer:(NSString *)bearer {
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    r.HTTPMethod = method;
    [r setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (form) {
        NSMutableArray *pairs = [NSMutableArray new];
        // RFC 3986 unreserved characters pass; everything else (spaces, '&', '=', non-ASCII) is %-escaped.
        static NSCharacterSet *ok;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            ok = [NSCharacterSet characterSetWithCharactersInString:
                  @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
        });
        for (NSString *k in form) {
            [pairs addObject:[NSString stringWithFormat:@"%@=%@",
                [k stringByAddingPercentEncodingWithAllowedCharacters:ok],
                [form[k] stringByAddingPercentEncodingWithAllowedCharacters:ok]]];
        }
        r.HTTPBody = [[pairs componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
        [r setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    } else if (json) {
        r.HTTPBody = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
        [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    if (bearer) [r setValue:[@"Bearer " stringByAppendingString:bearer] forHTTPHeaderField:@"Authorization"];
    Reply *out = [Reply new];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[self.session dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if ([resp isKindOfClass:NSHTTPURLResponse.class]) {
            out.body = data;
            out.status = ((NSHTTPURLResponse *)resp).statusCode;
            out.reached = YES;
        }
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    return out;
}

static void Main(void (^block)(void)) { dispatch_async(dispatch_get_main_queue(), block); }
static NSString *const kOffline = @"Could not reach Microsoft. Check your internet connection.";

- (void)cancel { self.cancelled = YES; }

- (void)requestDeviceCode:(HZDeviceCodeDone)done {
    NSString *client = HZActiveClientID();
    if (!client) { Main(^{ done(nil, HZSignInNotConfigured); }); return; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableDictionary *form = [@{ @"client_id": client, @"scope": ScopeForRequests() } mutableCopy];
        if (HZSignInIsTestMode()) form[@"response_type"] = @"device_code";   // live.com asks for it
        Reply *r = [self send:@"POST" url:DeviceCodeURL() form:form json:nil bearer:nil];
        if (!r.reached) { Main(^{ done(nil, kOffline); }); return; }
        NSString *error = nil;
        HZDeviceCode *code = r.status == 200 ? [HZDeviceCode parse:r.body error:&error] : nil;
        if (!code && !error) error = [HZPollOutcome parse:r.body status:r.status].message;
        Main(^{ done(code, code ? nil : error); });
    });
}

// Microsoft access token -> Minecraft access token (steps 3 to 5). On failure `error` says why.
- (NSString *)minecraftTokenFromMicrosoft:(NSString *)msAccess error:(NSString **)error {
    Reply *xbl = [self send:@"POST" url:kXboxUser form:nil json:@{
        @"Properties": @{ @"AuthMethod": @"RPS", @"SiteName": @"user.auth.xboxlive.com",
                          @"RpsTicket": RpsTicket(msAccess) },
        @"RelyingParty": @"http://auth.xboxlive.com", @"TokenType": @"JWT" } bearer:nil];
    if (!xbl.reached) { *error = @"Could not reach Xbox Live. Check your internet connection."; return nil; }
    // The first Xbox Live reply has only the token we send on to XSTS (the user hash comes with XSTS).
    id parsed = xbl.body.length ? [NSJSONSerialization JSONObjectWithData:xbl.body options:0 error:nil] : nil;
    NSString *xblToken = [parsed isKindOfClass:NSDictionary.class] ? parsed[@"Token"] : nil;
    if (xbl.status != 200 || ![xblToken isKindOfClass:NSString.class] || xblToken.length == 0) {
        *error = @"Xbox Live refused the sign-in.";
        return nil;
    }
    Reply *xsts = [self send:@"POST" url:kXsts form:nil json:@{
        @"Properties": @{ @"SandboxId": @"RETAIL", @"UserTokens": @[xblToken] },
        @"RelyingParty": @"rp://api.minecraftservices.com/", @"TokenType": @"JWT" } bearer:nil];
    if (!xsts.reached) { *error = @"Could not reach Xbox Live. Check your internet connection."; return nil; }
    HZXstsReply *x = [HZXstsReply parse:xsts.body status:xsts.status];
    if (!x.token) { *error = x.message; return nil; }
    Reply *mc = [self send:@"POST" url:[kMinecraft stringByAppendingString:@"/authentication/login_with_xbox"]
                     form:nil json:@{ @"identityToken": HZMinecraftIdentityToken(x.userHash, x.token) } bearer:nil];
    if (!mc.reached) { *error = @"Could not reach the Minecraft services. Check your internet connection."; return nil; }
    id mcJson = mc.body.length ? [NSJSONSerialization JSONObjectWithData:mc.body options:0 error:nil] : nil;
    NSString *token = [mcJson isKindOfClass:NSDictionary.class] ? mcJson[@"access_token"] : nil;
    if (mc.status == 200 && [token isKindOfClass:NSString.class] && token.length > 0) return token;
    if (mc.status == 403) *error = HZAppNotApproved;
    else if (mc.status == 429) *error = @"Too many sign-ins in a short time. Wait a minute and try again.";
    else *error = @"The Minecraft services refused the sign-in.";
    return nil;
}

// Steps 6 and 7 with a Minecraft token: owns the game, and the profile.
- (BOOL)checkGame:(NSString *)mcToken owns:(BOOL *)owns profile:(HZProfile **)profile error:(NSString **)error {
    Reply *e = [self send:@"GET" url:[kMinecraft stringByAppendingString:@"/entitlements/mcstore"]
                    form:nil json:nil bearer:mcToken];
    if (!e.reached) { *error = @"Could not reach the Minecraft services. Check your internet connection."; return NO; }
    if (e.status != 200) { *error = @"Could not check which games this account owns."; return NO; }
    *owns = HZOwnsJavaEdition(e.body);
    if (!*owns || !profile) return YES;
    Reply *p = [self send:@"GET" url:[kMinecraft stringByAppendingString:@"/minecraft/profile"]
                    form:nil json:nil bearer:mcToken];
    if (!p.reached) { *error = @"Could not reach the Minecraft services. Check your internet connection."; return NO; }
    NSString *message = nil;
    *profile = [HZProfile parse:p.body status:p.status message:&message];
    if (!*profile) { *error = message; return NO; }
    return YES;
}

- (void)completeSignIn:(HZDeviceCode *)code status:(void (^)(NSString *))status done:(HZSignInDone)done {
    NSString *client = HZActiveClientID();
    self.cancelled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        void (^fail)(NSString *) = ^(NSString *m) { Main(^{ done(nil, m); }); };
        if (!client) { fail(HZSignInNotConfigured); return; }
        Main(^{ status(@"Waiting for you to sign in..."); });
        // Poll at the code's interval until the player is done, the code runs out or they cancel.
        NSTimeInterval interval = code.interval;
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:code.expiresIn];
        NSString *msAccess = nil, *msRefresh = nil;
        while (!msAccess) {
            for (NSTimeInterval waited = 0; waited < interval; waited += 0.2) {
                if (self.cancelled) { fail(@"Sign-in cancelled."); return; }
                [NSThread sleepForTimeInterval:0.2];
            }
            if ([deadline timeIntervalSinceNow] < 0) { fail(@"The sign-in code expired. Start again."); return; }
            Reply *r = [self send:@"POST" url:TokenURL() form:@{
                @"grant_type": @"urn:ietf:params:oauth:grant-type:device_code",
                @"client_id": client, @"device_code": code.deviceCode } json:nil bearer:nil];
            if (!r.reached) continue;   // a dropped request while waiting is not the end of the sign-in
            HZPollOutcome *o = [HZPollOutcome parse:r.body status:r.status];
            if (o.result == HZPollSlowDown) interval += 5;
            else if (o.result == HZPollStopped) { fail(o.message); return; }
            else if (o.result == HZPollSignedIn) { msAccess = o.accessToken; msRefresh = o.refreshToken; }
        }
        Main(^{ status(@"Signing in to Xbox Live..."); });
        NSString *error = nil;
        NSString *mcToken = [self minecraftTokenFromMicrosoft:msAccess error:&error];
        if (!mcToken) { fail(error); return; }
        Main(^{ status(@"Checking that you own Minecraft: Java Edition..."); });
        BOOL owns = NO;
        HZProfile *profile = nil;
        if (![self checkGame:mcToken owns:&owns profile:&profile error:&error]) { fail(error); return; }
        if (!owns) { fail(HZDoesNotOwn); return; }
        HZAccountState *account = [HZAccountState new];
        account.name = profile.name;
        account.uuid = profile.uuid;
        account.owns = YES;
        if (![[HZAccountStore shared] saveAccount:account refreshToken:msRefresh minecraftToken:mcToken]) {
            fail(@"Could not keep the sign-in on this phone. Try again.");
            return;
        }
        Main(^{ done(account, nil); });
    });
}

- (void)recheck:(void (^)(BOOL, BOOL, NSString *))done {
    NSString *client = HZActiveClientID();
    NSString *refresh = [[HZAccountStore shared] refreshToken];
    if (!client || !refresh) { Main(^{ done(YES, NO, HZSignInAgain); }); return; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        Reply *r = [self send:@"POST" url:TokenURL() form:@{
            @"grant_type": @"refresh_token", @"client_id": client, @"refresh_token": refresh, @"scope": ScopeForRequests() } json:nil bearer:nil];
        // No answer at all is offline: the last answer stands (HZMayDownload).
        if (!r.reached) { Main(^{ done(NO, NO, nil); }); return; }
        HZPollOutcome *o = [HZPollOutcome parse:r.body status:r.status];
        if (o.result != HZPollSignedIn) { Main(^{ done(YES, NO, o.message ?: HZSignInAgain); }); return; }
        NSString *error = nil;
        NSString *mcToken = [self minecraftTokenFromMicrosoft:o.accessToken error:&error];
        if (!mcToken) { Main(^{ done(YES, NO, error); }); return; }
        BOOL owns = NO;
        if (![self checkGame:mcToken owns:&owns profile:NULL error:&error]) { Main(^{ done(YES, NO, error); }); return; }
        HZAccountState *a = [[HZAccountStore shared] account];
        if (a) [[HZAccountStore shared] saveAccount:a refreshToken:o.refreshToken minecraftToken:mcToken];
        [[HZAccountStore shared] saveOwns:owns];
        Main(^{ done(YES, owns, nil); });
    });
}
@end
