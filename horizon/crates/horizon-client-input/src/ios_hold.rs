//! The iOS app's "hold": the engine starts with the app, but waits for Play before it loads.
//!
//! Today Play on iOS relaunches the app (the launcher is one run, the game another). The in-process
//! Play (docs/IN_PROCESS_PLAY_DESIGN.md, M24 stage 3) keeps one process: `main` always starts the
//! engine, the SwiftUI launcher is presented over winit's window, and the engine's resource loader
//! waits here until the launcher says Play.
//!
//! Pure logic with no game state, so it runs under `cargo test`. **Off by default**: nothing waits
//! unless the shell calls [`arm`] before the engine starts, so every other build and run behaves
//! exactly as before.
//!
//! The shell talks to this through four calls (exported by the iOS bridge crate):
//! [`arm`] before the engine starts, [`play`] when the person presses Play, [`state`] to show what
//! the engine is doing, and [`cancel`] if the app is leaving for good.

use std::sync::{Condvar, Mutex};

/// Where the hold is. Only moves forward: Disarmed (the default) never changes unless armed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    /// Nothing waits: the engine loads at once, as it always has.
    Disarmed,
    /// The engine is up and its loader is waiting for [`play`].
    Waiting,
    /// Play was pressed: the loader runs (or ran).
    Released,
    /// The shell asked the loader to give up (the app is leaving). The loader must not load.
    Cancelled,
}

static STATE: Mutex<State> = Mutex::new(State::Disarmed);
static CHANGED: Condvar = Condvar::new();

fn lock() -> std::sync::MutexGuard<'static, State> {
    // A panic elsewhere must not stop the launcher from starting the game.
    STATE.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Called by the shell before the engine starts. After this the loader waits for [`play`].
/// Calling it again once released or cancelled changes nothing.
pub fn arm() {
    let mut state = lock();
    if *state == State::Disarmed {
        *state = State::Waiting;
    }
}

/// Whether the hold was armed (the engine must not require game files before a window exists).
pub fn armed() -> bool {
    *lock() != State::Disarmed
}

/// The person pressed Play: the loader may start. False when the hold was never armed, or was
/// cancelled (nothing will load).
pub fn play() -> bool {
    let mut state = lock();
    match *state {
        State::Waiting => {
            *state = State::Released;
            CHANGED.notify_all();
            true
        }
        State::Released => true,
        State::Disarmed | State::Cancelled => false,
    }
}

/// The app is leaving: a waiting loader returns without loading.
pub fn cancel() {
    let mut state = lock();
    if *state == State::Waiting {
        *state = State::Cancelled;
        CHANGED.notify_all();
    }
}

/// The current state, for the shell's display.
pub fn state() -> State {
    *lock()
}

/// For the loader thread, first thing it does: blocks until Play, and says whether to go on.
/// Returns at once with `true` when nothing is armed.
pub fn wait_for_play() -> bool {
    let mut state = lock();
    loop {
        match *state {
            State::Disarmed | State::Released => return true,
            State::Cancelled => return false,
            State::Waiting => {
                state = CHANGED
                    .wait(state)
                    .unwrap_or_else(|poisoned| poisoned.into_inner());
            }
        }
    }
}

// ---- Orientation (the launcher is portrait, the game is landscape) ----
//
// The engine's window used to be created landscape-only, which made an app that waits for Play start in
// landscape and turn to portrait under the launcher (a visible swap, with the engine's boot screen in it).
// While the hold waits, the window is created portrait-capable instead; once Play releases the hold it is
// switched to landscape, once. Unarmed (every other build and run) neither function changes anything.

static LANDSCAPE_SWITCHED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Whether a window created now should be portrait (the hold is armed and Play has not been pressed).
pub fn window_starts_portrait() -> bool {
    *lock() == State::Waiting
}

/// For the engine loop, every turn while loading: true exactly once, on the first turn after Play released the
/// hold, meaning "switch the window to landscape now". False when never armed, still waiting, or cancelled.
pub fn take_landscape_switch() -> bool {
    use std::sync::atomic::Ordering::SeqCst;
    *lock() == State::Released && !LANDSCAPE_SWITCHED.swap(true, SeqCst)
}

// ---- Quit Game back to the launcher (M24 stage 3, step 2; nothing calls `allow_quit_to_launcher` yet) ----
//
// Same rule as the hold: off unless the shell turns it on, so every build behaves as before. When it is on,
// Quit Game asks [`request_quit`] first; a `true` answer means "the shell will take the engine back to Idle,
// do not end the process", `false` means "end the process as always".

static QUIT_ALLOWED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static QUIT_REQUESTED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// The shell says Quit Game may return to the launcher instead of ending the process.
/// Only meaningful once the hold is armed; without it [`request_quit`] still answers `false`.
pub fn allow_quit_to_launcher() {
    QUIT_ALLOWED.store(true, std::sync::atomic::Ordering::SeqCst);
}

/// Quit Game was chosen. `true`: the request is recorded and the process must NOT end (the engine loop turns it
/// into Idle through [`take_quit_request`]). `false`: not allowed, end the process as before.
pub fn request_quit() -> bool {
    use std::sync::atomic::Ordering::SeqCst;
    if !armed() || !QUIT_ALLOWED.load(SeqCst) {
        return false;
    }
    QUIT_REQUESTED.store(true, SeqCst);
    true
}

/// For the engine loop, once per turn: whether a quit was requested since the last call (and clears it).
pub fn take_quit_request() -> bool {
    QUIT_REQUESTED.swap(false, std::sync::atomic::Ordering::SeqCst)
}

/// The engine is back to Idle: the hold waits for Play again, so the next Play loads a fresh game.
/// A cancelled hold stays cancelled.
pub fn rearm_after_quit() {
    let mut state = lock();
    if *state == State::Released {
        *state = State::Waiting;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;
    use std::time::Duration;

    /// The state is process-wide, so the tests run one after another through this lock.
    static SERIAL: Mutex<()> = Mutex::new(());

    fn reset() {
        *lock() = State::Disarmed;
    }

    #[test]
    fn orientation_follows_the_hold() {
        let _serial = SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        reset();
        LANDSCAPE_SWITCHED.store(false, std::sync::atomic::Ordering::SeqCst);
        // Never armed: landscape as always, and no switch is ever asked for.
        assert!(!window_starts_portrait());
        assert!(!take_landscape_switch());
        arm();
        assert!(window_starts_portrait());
        assert!(!take_landscape_switch(), "still waiting for Play");
        assert!(play());
        assert!(!window_starts_portrait());
        assert!(take_landscape_switch(), "the first turn after Play");
        assert!(!take_landscape_switch(), "only once");
        reset();
    }

    #[test]
    fn disarmed_never_waits() {
        let _serial = SERIAL.lock().unwrap();
        reset();
        assert!(!armed());
        assert!(wait_for_play(), "a disarmed hold lets the loader go at once");
        assert!(!play(), "nothing was waiting");
        assert_eq!(state(), State::Disarmed);
    }

    #[test]
    fn loader_waits_until_play() {
        let _serial = SERIAL.lock().unwrap();
        reset();
        arm();
        assert!(armed());
        assert_eq!(state(), State::Waiting);
        let (sender, receiver) = mpsc::channel();
        let loader = std::thread::spawn(move || {
            let go = wait_for_play();
            sender.send(go).unwrap();
        });
        assert!(
            receiver.recv_timeout(Duration::from_millis(150)).is_err(),
            "the loader must still be waiting"
        );
        assert!(play());
        assert_eq!(receiver.recv_timeout(Duration::from_secs(5)), Ok(true));
        loader.join().unwrap();
        assert_eq!(state(), State::Released);
    }

    #[test]
    fn cancel_frees_a_waiting_loader_without_loading() {
        let _serial = SERIAL.lock().unwrap();
        reset();
        arm();
        let (sender, receiver) = mpsc::channel();
        let loader = std::thread::spawn(move || sender.send(wait_for_play()).unwrap());
        assert!(receiver.recv_timeout(Duration::from_millis(100)).is_err());
        cancel();
        assert_eq!(receiver.recv_timeout(Duration::from_secs(5)), Ok(false));
        loader.join().unwrap();
        assert!(!play(), "a cancelled hold cannot be released");
    }

    #[test]
    fn arming_twice_or_after_release_changes_nothing() {
        let _serial = SERIAL.lock().unwrap();
        reset();
        arm();
        arm();
        assert_eq!(state(), State::Waiting);
        assert!(play());
        arm();
        assert_eq!(state(), State::Released);
        assert!(play(), "pressing Play twice is harmless");
        cancel();
        assert_eq!(state(), State::Released, "a started game is not cancelled");
    }

    #[test]
    fn quit_is_refused_unless_armed_and_allowed() {
        let _serial = SERIAL.lock().unwrap();
        reset();
        QUIT_ALLOWED.store(false, std::sync::atomic::Ordering::SeqCst);
        QUIT_REQUESTED.store(false, std::sync::atomic::Ordering::SeqCst);
        assert!(!request_quit(), "disarmed: the process ends as always");
        arm();
        assert!(!request_quit(), "armed but not allowed: the process ends as always");
        assert!(!take_quit_request());
        allow_quit_to_launcher();
        assert!(request_quit());
        assert!(take_quit_request());
        assert!(!take_quit_request(), "taking it clears it");
        QUIT_ALLOWED.store(false, std::sync::atomic::Ordering::SeqCst);
    }

    #[test]
    fn after_a_quit_the_next_play_loads_again() {
        let _serial = SERIAL.lock().unwrap();
        reset();
        arm();
        assert!(play());
        rearm_after_quit();
        assert_eq!(state(), State::Waiting);
        let (sender, receiver) = mpsc::channel();
        let loader = std::thread::spawn(move || sender.send(wait_for_play()).unwrap());
        assert!(receiver.recv_timeout(Duration::from_millis(100)).is_err(), "must wait for the second Play");
        assert!(play());
        assert_eq!(receiver.recv_timeout(Duration::from_secs(5)), Ok(true));
        loader.join().unwrap();
        // A cancelled hold is not re-armed.
        cancel();
        reset();
        arm();
        cancel();
        rearm_after_quit();
        assert_eq!(state(), State::Cancelled);
    }
}
