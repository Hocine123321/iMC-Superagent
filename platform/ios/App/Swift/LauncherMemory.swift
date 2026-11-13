import UIKit

/// What the launcher keeps in memory to be quick, given back when it goes away. With Play without closing the app the
/// launcher and the game share one process, and on a phone with 4 GB the game wants every megabyte iOS lets it have.
enum LauncherMemory {
    static func releaseAll() {
        BackdropCache.release()
        MarkdownLite.releaseMemo()
        URLCache.shared.removeAllCachedResponses()   // icons and screenshots the Marketplace showed
        HZTheme.flushSettings()
    }
}
