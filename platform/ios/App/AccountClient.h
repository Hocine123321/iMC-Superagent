// The requests of the sign-in: Microsoft, Xbox Live, XSTS and the Minecraft services, in the order
// of horizon/docs/microsoft-account.md. The wording of every refusal is in AccountModel.m; this
// file only sends and reads. All calls come back on the main thread.
//
// An ephemeral session: no cookie jar, no cache, nothing written to disk, so a token cannot linger
// in a URL cache. No request or reply body is ever logged.
#import <Foundation/Foundation.h>
#import "AccountModel.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^HZDeviceCodeDone)(HZDeviceCode *_Nullable code, NSString *_Nullable error);
typedef void (^HZSignInDone)(HZAccountState *_Nullable account, NSString *_Nullable error);

@interface HZAccountClient : NSObject
+ (instancetype)shared;

// Step 1: asks Microsoft for a code to show. `error` is a message for the player.
- (void)requestDeviceCode:(HZDeviceCodeDone)done;

// Steps 2 to 7, once the player has typed the code: waits for the Microsoft sign-in (polling at the
// code's interval), then Xbox Live, XSTS, the Minecraft login, the ownership check and the profile.
// `status` is a short line for the screen ("Waiting for you to sign in...", "Checking the game...").
// Saves the account and its secrets on success. Call `cancel` to stop waiting.
- (void)completeSignIn:(HZDeviceCode *)code
                status:(void (^)(NSString *line))status
                  done:(HZSignInDone)done;
- (void)cancel;

// Checks again, with the saved refresh token, that the account still owns the game. `reachable` is NO
// when the services could not be reached (offline), in which case the last answer stands.
- (void)recheck:(void (^)(BOOL reachable, BOOL owns, NSString *_Nullable error))done;
@end

NS_ASSUME_NONNULL_END
