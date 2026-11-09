// Microsoft sign-in, with no user interface and no network: the rules only.
//
// The flow is the one in horizon/docs/microsoft-account.md (OAuth device code, Xbox Live, XSTS,
// the Minecraft services, the ownership check). This file holds the parts that are decisions about
// text: reading each reply, turning the refusal codes into the documented messages, and deciding
// whether the account owns Minecraft: Java Edition. AccountClient.m does the requests,
// AccountStore.m keeps the secrets, AccountScreen.m shows it.
//
// What this project does NOT have: its own Azure app. The client ID is the owner's to register
// (docs/IOS_SIGN_IN.md), and until Mojang approves it the last step answers 403. A build with no
// client ID says so and nothing else is attempted. Never use another application's client ID.
//
// Tokens are never logged, never put in an error and never shown. Everything below that carries one
// is a plain NSString the caller keeps out of NSLog.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The build's client ID (Info.plist key HZMicrosoftClientID, filled from the build), or nil when
// there is none. The environment variable HORIZON_MSA_CLIENT_ID wins, as on desktop; an empty
// value means none.
NSString *_Nullable HZMicrosoftClientID(void);

// Said while there is no client ID, in place of a sign-in.
extern NSString *const HZSignInNotConfigured;
// Said when the account does not own the game.
extern NSString *const HZDoesNotOwn;
// Said when the account owns the game but has no profile yet.
extern NSString *const HZNoProfile;
// Said when the sign-in expired and the player has to do it again.
extern NSString *const HZSignInAgain;
// Said when Mojang has not approved this app's client ID yet (login_with_xbox answered 403).
extern NSString *const HZAppNotApproved;

// The first reply: what to show the player while they sign in on the Microsoft page.
@interface HZDeviceCode : NSObject
@property (nonatomic, copy) NSString *deviceCode;       // secret: sent back when polling, never shown
@property (nonatomic, copy) NSString *userCode;         // what the player types
@property (nonatomic, copy) NSString *verificationURI;  // https://www.microsoft.com/link
@property (nonatomic) NSTimeInterval interval;          // seconds between polls (5 when absent)
@property (nonatomic) NSTimeInterval expiresIn;         // seconds the code lives
// Reads the devicecode reply. nil and `error` (a message) when it is not usable.
+ (nullable instancetype)parse:(NSData *)body error:(NSString *_Nullable *_Nullable)error;
@end

typedef NS_ENUM(NSInteger, HZPollResult) {
    HZPollPending,    // the player has not finished: ask again after `interval`
    HZPollSlowDown,   // ask again, 5 seconds slower
    HZPollSignedIn,   // `accessToken` and `refreshToken` are set
    HZPollStopped,    // declined, expired or a bad code: `message` says which; do not ask again
};

// One answer from the token endpoint.
@interface HZPollOutcome : NSObject
@property (nonatomic) HZPollResult result;
@property (nonatomic, copy, nullable) NSString *accessToken;   // secret
@property (nonatomic, copy, nullable) NSString *refreshToken;  // secret
@property (nonatomic, copy, nullable) NSString *message;       // for HZPollStopped
// `body` is the reply, `status` its HTTP status. Never fails: an unreadable reply stops with a message.
+ (instancetype)parse:(NSData *)body status:(NSInteger)status;
@end

// The XSTS refusal codes (XErr) turned into the words the desktop launcher uses; nil when the code is
// not one it knows.
NSString *_Nullable HZXstsMessage(long long xerr);

// An XSTS reply: the token and the user hash that go into the Minecraft login, or the message.
@interface HZXstsReply : NSObject
@property (nonatomic, copy, nullable) NSString *token;      // secret
@property (nonatomic, copy, nullable) NSString *userHash;   // uhs
@property (nonatomic, copy, nullable) NSString *message;    // set when there is no token
+ (instancetype)parse:(NSData *)body status:(NSInteger)status;
@end

// The identityToken the Minecraft login takes: "XBL3.0 x=<uhs>;<xsts token>".
NSString *HZMinecraftIdentityToken(NSString *userHash, NSString *xstsToken);

// The entitlements reply: does the account own the Java Edition (game_minecraft or product_minecraft,
// Game Pass included)? Anything unreadable is "no", so a damaged reply never opens the gate.
BOOL HZOwnsJavaEdition(NSData *entitlementsBody);

// The profile reply (name, id). `status` 404 is "owns the game but has no profile yet".
@interface HZProfile : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *uuid;   // 32 hex digits, as the services send it
+ (nullable instancetype)parse:(NSData *)body status:(NSInteger)status message:(NSString *_Nullable *_Nullable)message;
@end

// What the launcher knows about the signed-in account, kept between runs (no secret in it).
@interface HZAccountState : NSObject
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, copy, nullable) NSString *uuid;
// The last ownership answer. YES passed before; offline never takes it back.
@property (nonatomic) BOOL owns;
@end

// Whether the download may start. The one place the gate lives.
//   signedIn  : there is an account with a saved answer
//   owns      : the last answer was yes
//   reachable : the services answered just now; NO when offline
//   freshAnswer: with `reachable`, what they said (YES owns)
// A fresh "no" blocks at once. With no network the last answer stands, so being offline never blocks a
// player who passed before. No account, or no past yes, blocks.
BOOL HZMayDownload(BOOL signedIn, BOOL owns, BOOL reachable, BOOL freshAnswer);

NS_ASSUME_NONNULL_END
