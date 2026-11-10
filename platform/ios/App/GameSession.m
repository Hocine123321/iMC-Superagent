#import "GameSession.h"
#import "AccountStore.h"
#import <sys/stat.h>

static NSString *const kFileName = @"game-session.json";

static BOOL IsUUID(NSString *s) {
    NSString *hex = [s stringByReplacingOccurrencesOfString:@"-" withString:@""];
    if (hex.length != 32) return NO;
    for (NSUInteger i = 0; i < hex.length; i++) {
        unichar c = [hex characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return NO;
    }
    return YES;
}

NSData *HZSessionFileData(NSString *name, NSString *uuid, NSString *token) {
    // The engine counts characters, not bytes: a profile name is ASCII anyway.
    if (name.length < 1 || name.length > 16 || !uuid || !IsUUID(uuid) || token.length == 0) return nil;
    NSDictionary *json = @{ @"name": name, @"uuid": uuid, @"access_token": token, @"user_type": @"msa" };
    return [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
}

NSString *HZWriteGameSession(NSString *folder) {
    HZAccountStore *store = [HZAccountStore shared];
    HZAccountState *a = [store account];
    NSData *data = a ? HZSessionFileData(a.name, a.uuid, [store minecraftToken]) : nil;
    if (!data) return nil;
    NSString *path = [folder stringByAppendingPathComponent:kFileName];
    // Created with 0600 from the start (not written, then restricted), so there is no moment
    // when another process could read it.
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    BOOL ok = [NSFileManager.defaultManager createFileAtPath:path contents:data
                                                  attributes:@{ NSFilePosixPermissions: @(0600) }];
    if (!ok) return nil;
    // The mode really is 0600 (umask can only remove bits, but the engine refuses anything else).
    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) != 0 || (st.st_mode & 0077) != 0) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        return nil;
    }
    return path;
}

void HZRemoveStaleGameSession(NSString *folder) {
    [NSFileManager.defaultManager removeItemAtPath:[folder stringByAppendingPathComponent:kFileName] error:nil];
}

void HZNoteGameSession(NSString *folder, BOOL handedOver) {
    HZAccountState *a = [[HZAccountStore shared] account];
    NSString *text = handedOver
        ? [NSString stringWithFormat:@"game account: handed to the game as %@ (the token is not shown)\n", a.name ?: @"?"]
        : (a ? @"game account: signed in, but the session file could not be made, so the game starts offline\n"
             : @"game account: nobody signed in, the game starts offline\n");
    NSString *path = [folder stringByAppendingPathComponent:@"diagnostics.txt"];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!h) { [text writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil]; return; }
    [h seekToEndOfFile];
    [h writeData:[text dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}
