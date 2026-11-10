// The signed-in account, handed to the game. The engine takes an account from a "session file"
// (--session-file, crates/horizon-client-render/src/auth.rs AuthSession): JSON with the player's
// name, UUID and Minecraft access token. With it the game plays as that profile (name, UUID, and
// the token for online servers); without it, it plays offline under a generated name.
//
// The engine is strict about that file, and this follows its rules exactly:
//  - it reads the file once and deletes it, so a token does not stay on the disk;
//  - it refuses a file older than 120 seconds, so the file is written just before the engine starts
//    (main.m), never earlier;
//  - it refuses a file that group or others can read, so it is written with mode 0600;
//  - the name is 1 to 16 characters, the UUID 32 hex digits (dashes allowed), the token not empty.
//
// This does NOT gate playing. Owning the game gates only the download (docs/IOS_SIGN_IN.md): a
// signed-in account that is offline, expired or not confirmed still starts the game. The token is
// only as fresh as the last sign-in or ownership check (about a day); a stale one makes online
// servers refuse the player, never singleplayer or LAN.
//
// A token is never logged, never put in an error and never returned to a screen.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The session file's bytes, or nil when any part is missing or unusable (then the game plays
// offline). Pure: no disk, no Keychain, so the rules can be tested.
NSData *_Nullable HZSessionFileData(NSString *_Nullable name, NSString *_Nullable uuid, NSString *_Nullable token);

// Writes the session for the saved account into `folder` (mode 0600) and returns its path, or nil
// when nobody is signed in or the file could not be written. Call it right before the engine starts.
NSString *_Nullable HZWriteGameSession(NSString *folder);

// Adds one line to diagnostics.txt (which the Diagnostics screen shares) saying whether an account
// was handed to the game, and the profile name if so. Never the UUID, never a token.
void HZNoteGameSession(NSString *folder, BOOL handedOver);

// Deletes a session file an earlier run left (the engine deletes it on read, but a run that ended
// before the engine started would leave one). Safe when there is none.
void HZRemoveStaleGameSession(NSString *folder);

NS_ASSUME_NONNULL_END
