//! Auto Performance, the game's side (`horizon_client_input::auto_performance` holds the rules).
//!
//! Every 5 seconds it asks iOS how much more memory the app may use. That is one counter read
//! (`os_proc_available_memory`), so the frame loop pays an `Instant` comparison on the other
//! frames and a few microseconds on this one. The answer goes to the governor, which says how
//! far the render distance, the far terrain and the resolution may go right now. Those caps are
//! applied on top of the player's settings where they are read, and the player's own values in
//! `options.txt` are never rewritten.
use super::Game;
use horizon_client_input::auto_performance::{CHECK_EVERY_SECS, Caps, Wanted};
use std::time::{Duration, Instant};

/// The state the game keeps between frames.
#[derive(Debug, Default)]
pub(super) struct AutoPerformance {
    governor: horizon_client_input::auto_performance::Governor,
    last_check: Option<Instant>,
    /// The caps in force now.
    pub(super) caps: Caps,
}

impl Game<'_> {
    /// Called every frame. Does nothing until the next reading is due.
    pub(super) fn auto_performance_frame(&mut self) {
        let due = self
            .auto_performance
            .last_check
            .is_none_or(|at| at.elapsed() >= Duration::from_secs_f64(CHECK_EVERY_SECS));
        if !due {
            return;
        }
        self.auto_performance.last_check = Some(Instant::now());
        let config = self.settings.imc.auto.clone();
        let available_mb = horizon_threads::process_memory::available_bytes().map(|b| b >> 20);
        let wanted = Wanted {
            render_distance: self.settings.render_distance.max(0) as u32,
            lod_distance: self.settings.horizon.lod_distance,
            resolution_scale: self.settings.horizon.resolution_scale,
        };
        let now = self.started.elapsed().as_secs_f64();
        let caps = self
            .auto_performance
            .governor
            .tick(&config, wanted, available_mb, now);
        if caps == self.auto_performance.caps {
            return;
        }
        log::info!(
            "Horizon: Auto Performance {} ({} MB available): render distance {:?}, far terrain {:?}, resolution {:?}",
            if caps.any() { "holding back" } else { "lifted" },
            available_mb.unwrap_or(0),
            caps.render_distance,
            caps.lod_distance,
            caps.resolution_scale,
        );
        self.auto_performance.caps = caps;
        // The same path a change in Options takes: the radius, the sections and the post pass.
        self.apply_settings();
    }

    /// The player's render distance, held to the cap.
    pub(super) fn capped_render_distance(&self) -> i32 {
        let wanted = self.settings.render_distance;
        match self.auto_performance.caps.render_distance {
            Some(cap) => wanted.min(cap as i32),
            None => wanted,
        }
    }

    /// The player's world resolution scale, held to the cap.
    pub(super) fn capped_resolution_scale(&self) -> u32 {
        horizon_client_input::auto_performance::capped(
            self.settings.horizon.resolution_scale,
            self.auto_performance.caps.resolution_scale,
        )
    }

    /// One line for the options page: whether anything is held back right now.
    pub(super) fn auto_performance_status(&self) -> Option<String> {
        let caps = self.auto_performance.caps;
        if !self.settings.imc.auto.enabled {
            return None;
        }
        if !caps.any() {
            return Some("Auto Performance: nothing held back".to_owned());
        }
        let mut parts = Vec::new();
        if let Some(d) = caps.render_distance {
            parts.push(format!("render distance {d}"));
        }
        if let Some(d) = caps.lod_distance {
            parts.push(if d == 0 {
                "far terrain off".to_owned()
            } else {
                format!("far terrain {d}")
            });
        }
        if let Some(s) = caps.resolution_scale {
            parts.push(format!("resolution {s}%"));
        }
        Some(format!(
            "Auto Performance is holding back: {}",
            parts.join(", ")
        ))
    }
}
