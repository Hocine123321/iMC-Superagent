// Where the sign-in lives between runs.
//
// The two secrets (the Microsoft refresh token and the Minecraft access token) are kept in the iOS
// Keychain, one item each, readable only on this phone and only after its first unlock since a
// restart (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly): they do not go into a backup or onto
// another device. The name, the UUID and the last ownership answer carry no secret and sit in
// <root>/account.txt beside the other launcher settings, so the launcher can show them without
// asking the Keychain. Signing out deletes both Keychain items and that file.
//
// Nothing here logs a token, puts one in an error or returns one to the screens: the screens ask
// for "is there an account" and "what is its name", and the client reads the secrets itself.
#import <Foundation/Foundation.h>
#import "AccountModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface HZAccountStore : NSObject
+ (instancetype)shared;

// The saved account, or nil when nobody is signed in.
- (nullable HZAccountState *)account;
// Saves the account (no secret) and its secrets. NO if the Keychain refused either.
- (BOOL)saveAccount:(HZAccountState *)account refreshToken:(NSString *)refresh minecraftToken:(NSString *)minecraft;
// Replaces only the last ownership answer, after a check.
- (void)saveOwns:(BOOL)owns;
- (nullable NSString *)refreshToken;
- (nullable NSString *)minecraftToken;
// Deletes both Keychain items and the account file. Safe when there is nothing to delete.
- (void)signOut;
@end

NS_ASSUME_NONNULL_END
