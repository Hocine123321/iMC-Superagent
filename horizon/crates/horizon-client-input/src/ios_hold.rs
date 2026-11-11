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
}
