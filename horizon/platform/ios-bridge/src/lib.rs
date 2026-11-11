//! The iOS app's way into Horizon.
//!
//! winit's `EventLoop::run_app` calls `UIApplicationMain` itself on iOS, so the Xcode project
//! declares no app delegate: its `main` calls [`horizon_ios_main`] with the process's own
//! `argc` and `argv`, and this hands them to the same startup every desktop build runs
//! (`horizon_client::entry::main`, which reads `std::env::args()`).
//!
//! The global allocator is the executable's job in this repository (`crates/horizon-client/src/main.rs`),
//! so it is set here too: a static library has the same single owner for it.

// The one `unsafe` this crate needs is the exported symbol's attribute.
#![allow(unsafe_code)]

#[cfg(not(any(feature = "system-allocator", feature = "alloc-census")))]
#[global_allocator]
static ALLOCATOR: horizon_threads::Allocator = horizon_threads::ALLOCATOR;

/// The mod API level this game serves, kept in the program for the launcher to read
/// (`horizon_mods::api_level::MARK`). `horizon_ios_main` reads it so the linker keeps it.
static MOD_API_LEVEL: [u8; 27] = horizon_mods::api_level::MARK;

/// Starts the game and does not return until it ends (winit's `run_app` never returns on iOS).
///
/// `argc` and `argv` are the ones `main` received; Rust's `std::env::args()` reads the same
/// process arguments, so nothing needs to be passed through.
#[unsafe(no_mangle)]
pub extern "C" fn horizon_ios_main() {
    std::hint::black_box(&MOD_API_LEVEL);
    let _ = horizon_client::gfx::BREADCRUMB.set(breadcrumb);
    horizon_client::entry::main();
}

/// Play without closing the app (docs/IN_PROCESS_PLAY_DESIGN.md, M24 stage 3): call this before
/// [`horizon_ios_main`], on the same thread. The engine then starts as usual, shows its window, and
/// its resource loader waits until [`horizon_ios_play`]. Never called, nothing changes.
#[unsafe(no_mangle)]
pub extern "C" fn horizon_ios_arm_hold() {
    horizon_client::ios_hold::arm();
}

/// The person pressed Play. Returns true when the engine was waiting (or already started), false
/// when the hold was never armed or the app is leaving. Safe to call from any thread.
#[unsafe(no_mangle)]
pub extern "C" fn horizon_ios_play() -> bool {
    horizon_client::ios_hold::play()
}

/// The app is leaving for good: a waiting loader returns without loading. Safe from any thread.
#[unsafe(no_mangle)]
pub extern "C" fn horizon_ios_cancel_hold() {
    horizon_client::ios_hold::cancel();
}

/// Where the hold is: 0 not armed, 1 waiting for Play, 2 released (Play was pressed), 3 cancelled.
#[unsafe(no_mangle)]
pub extern "C" fn horizon_ios_hold_state() -> i32 {
    use horizon_client::ios_hold::State;
    match horizon_client::ios_hold::state() {
        State::Disarmed => 0,
        State::Waiting => 1,
        State::Released => 2,
        State::Cancelled => 3,
    }
}

unsafe extern "C" {
    /// The shell's crash reporter (`platform/ios/App/CrashReporter.m`): remembers the step and
    /// writes it to crash.txt, so a crash report says how far the game got.
    fn horizon_ios_breadcrumb(step: *const std::ffi::c_char);
}

/// The step the game has reached, handed to the shell.
fn breadcrumb(step: &str) {
    if let Ok(step) = std::ffi::CString::new(step) {
        // SAFETY: the shell copies the text before it returns, and `step` lives until then.
        unsafe { horizon_ios_breadcrumb(step.as_ptr()) };
    }
}
