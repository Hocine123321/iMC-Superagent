//! The phone's app lifecycle: the app goes inactive (Control Center, a call, the home
//! gesture) and the system may then end it without warning, or it warns that memory is short.
//!
//! winit calls `suspended` for iOS `applicationWillResignActive` and `memory_warning` for
//! `applicationDidReceiveMemoryWarning`. Nothing here ends the session: the world is saved in
//! place, as `horizon-ctl save` does, so coming back finds the game as it was.
use super::event_loop::EventLoopCtl;
use super::{Game, Screen};
use std::time::{Duration, Instant};

/// A save on every Control Center pull would stall the game each time: no more often than this.
const SUSPEND_SAVE_EVERY: Duration = Duration::from_secs(30);

impl Game<'_> {
    /// The app is no longer the active one: let go of every held input, then save the world.
    pub(super) fn app_suspended(&mut self, event_loop: &dyn EventLoopCtl) {
        // A finger that went down before the app left never sends its release.
        self.touch_release_all(event_loop);
        self.pad_cancel_inputs(event_loop);
        if !self.suspend_save_due() {
            return;
        }
        match self.save_game() {
            Ok(()) => self.last_suspend_save = Some(Instant::now()),
            Err(e) => log::warn!("Horizon: saving as the app went inactive failed: {e}"),
        }
    }

    /// A world of this window's own is open and nothing is already closing it.
    fn suspend_save_due(&self) -> bool {
        self.title.is_none()
            && self.remote.is_none()
            && self.pending_save.is_none()
            && !self.saved_for_exit
            && self.screen != Screen::Win
            && self
                .last_suspend_save
                .is_none_or(|at| at.elapsed() >= SUSPEND_SAVE_EVERY)
    }

    /// The system is short of memory: hand back what the allocator holds free. It frees only
    /// pages nothing uses, so nothing the game needs is lost.
    pub(super) fn app_memory_warning(&mut self) {
        log::warn!("Horizon: memory warning from the system");
        horizon_threads::release_free_memory();
    }
}
