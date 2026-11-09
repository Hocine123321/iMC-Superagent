//! Auto Performance: gives memory back when the phone is running short, and takes the
//! quality back when it is not.
//!
//! Pure logic with no game state, so it runs under `cargo test`. Every few seconds the game reads
//! how much more memory iOS will let the app use (`os_proc_available_memory`, one kernel counter,
//! no allocation) and hands it to [`Governor::tick`], which answers with a [`Caps`]: the most the
//! render distance, the far-terrain distance and the resolution scale may be right now.
//!
//! **It never touches the player's saved settings.** The caps are applied on top of them for as
//! long as memory is short and lifted when it recovers, so a bad minute in a crowded area does not
//! leave the render distance lower for good. The choices it makes, in order, cost the least
//! picture for the most memory:
//!
//! 1. **Far terrain** (`lod_distance`): tiles and meshes beyond the render distance, which only
//!    the horizon shows. Cut first, and cut to nothing if it must be.
//! 2. **Render distance**: the loaded columns, their meshes and the GPU arenas, the largest
//!    single cost. One chunk at a time, never below the player's chosen floor.
//! 3. **Resolution scale**: the render targets. Last, because it is the one the player sees on
//!    every pixel.
//!
//! Changing the render distance meshes every section again, so the governor is slow to give
//! quality back: memory has to stay comfortable for several readings in a row before it lifts a
//! cap by one step, and it never moves twice in one reading.

/// How often the game should call [`Governor::tick`], in seconds.
pub const CHECK_EVERY_SECS: f64 = 5.0;

/// How soon after a step down the next step down may come, in seconds. A render distance change
/// takes a moment to show in the memory figure; this keeps one squeeze from being answered
/// three times over.
const SETTLE_SECS: f64 = 10.0;

/// The most the governor lets each setting be. `None` is "no cap: the player's own value".
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Caps {
    /// The render distance, in chunks.
    pub render_distance: Option<u32>,
    /// The far-terrain distance, in chunks. `Some(0)` turns far terrain off.
    pub lod_distance: Option<u32>,
    /// The world resolution as a percentage of the window's.
    pub resolution_scale: Option<u32>,
}

impl Caps {
    /// Whether any cap is in force.
    pub fn any(&self) -> bool {
        *self != Caps::default()
    }
}

/// How early the governor acts, as a share of the memory iOS will still give the app.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Sensitivity {
    /// Acts only when the app is close to the limit.
    Relaxed,
    Balanced,
    /// Acts while there is still room, for a phone that is also running other apps.
    Early,
}

impl Sensitivity {
    pub const ALL: [Sensitivity; 3] = [
        Sensitivity::Relaxed,
        Sensitivity::Balanced,
        Sensitivity::Early,
    ];

    /// Below this many megabytes available, the governor steps down.
    pub fn low_mb(self) -> u64 {
        match self {
            Sensitivity::Relaxed => 350,
            Sensitivity::Balanced => 500,
            Sensitivity::Early => 700,
        }
    }

    /// Above this many megabytes available, memory counts as comfortable and a cap may lift.
    /// Well above [`low_mb`](Self::low_mb), so a reading hovering near one line cannot flap.
    pub fn comfortable_mb(self) -> u64 {
        self.low_mb() + 300
    }

    /// Below this many megabytes available the app is about to be ended: every lever at once.
    pub fn critical_mb(self) -> u64 {
        self.low_mb() * 2 / 5
    }

    pub fn name(self) -> &'static str {
        match self {
            Sensitivity::Relaxed => "Relaxed",
            Sensitivity::Balanced => "Balanced",
            Sensitivity::Early => "Early",
        }
    }
}

/// What the player has chosen for Auto Performance.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Config {
    /// The feature's switch.
    pub enabled: bool,
    pub sensitivity: Sensitivity,
    /// The render distance the governor never goes below, in chunks.
    pub min_render_distance: u32,
    /// May cut far terrain.
    pub use_far_terrain: bool,
    /// May lower the render distance.
    pub use_render_distance: bool,
    /// May lower the resolution scale.
    pub use_resolution: bool,
}

impl Default for Config {
    /// Off, as every Horizon extra is. When switched on: balanced, a floor of 6 chunks, far
    /// terrain and render distance allowed, resolution left alone (it is the one the player
    /// sees on every pixel, so it is opt-in).
    fn default() -> Self {
        Config {
            enabled: false,
            sensitivity: Sensitivity::Balanced,
            min_render_distance: 6,
            use_far_terrain: true,
            use_render_distance: true,
            use_resolution: false,
        }
    }
}

/// The player's own values the governor starts from, read each tick.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Wanted {
    pub render_distance: u32,
    pub lod_distance: u32,
    pub resolution_scale: u32,
}

/// The resolution scales the governor steps through, from the top.
const SCALE_STEPS: [u32; 4] = [100, 85, 70, 55];

/// The state between readings.
#[derive(Clone, Debug, Default)]
pub struct Governor {
    /// How many steps down the governor is, in the order it takes them.
    level: u32,
    /// Readings in a row that were comfortable.
    comfortable_streak: u32,
    /// When the last step down happened, in the caller's seconds.
    last_step_at: Option<f64>,
}

/// How many comfortable readings in a row it takes to give one step back (6 x 5 s = 30 s).
const RECOVER_AFTER: u32 = 6;

impl Governor {
    pub fn new() -> Self {
        Governor::default()
    }

    /// Whether the governor is holding anything back right now.
    pub fn level(&self) -> u32 {
        self.level
    }

    /// Forgets everything: the feature was switched off, or a different world opened.
    pub fn reset(&mut self) {
        *self = Governor::default();
    }

    /// One reading. `available_mb` is what iOS will still give the app (`None` where the system
    /// does not say: nothing is capped), `now` the caller's clock in seconds. Returns the caps to
    /// apply until the next reading.
    pub fn tick(
        &mut self,
        config: &Config,
        wanted: Wanted,
        available_mb: Option<u64>,
        now: f64,
    ) -> Caps {
        let Some(available) = available_mb.filter(|_| config.enabled) else {
            self.reset();
            return Caps::default();
        };
        let steps = self.steps(config, wanted);
        let max_level = steps.len() as u32;
        let s = config.sensitivity;
        let settled = self.last_step_at.is_none_or(|at| now - at >= SETTLE_SECS);
        if available < s.critical_mb() {
            // About to be ended: every lever at once, without waiting for the settle time.
            self.level = max_level;
            self.last_step_at = Some(now);
            self.comfortable_streak = 0;
        } else if available < s.low_mb() {
            self.comfortable_streak = 0;
            if settled && self.level < max_level {
                self.level += 1;
                self.last_step_at = Some(now);
            }
        } else if available >= s.comfortable_mb() {
            self.comfortable_streak += 1;
            if self.comfortable_streak >= RECOVER_AFTER && self.level > 0 {
                self.level -= 1;
                self.comfortable_streak = 0;
            }
        } else {
            // Between the lines: hold what is set, and count nothing toward recovery.
            self.comfortable_streak = 0;
        }
        self.caps_at(self.level.min(max_level), &steps)
    }

    /// The ordered steps this configuration allows, each a cap to add on top of the last.
    fn steps(&self, config: &Config, wanted: Wanted) -> Vec<Step> {
        let mut steps = Vec::new();
        if config.use_far_terrain && wanted.lod_distance > 0 {
            // Half, then a quarter, then none: three cuts on the cheapest thing to lose.
            for d in [wanted.lod_distance / 2, wanted.lod_distance / 4, 0] {
                if steps.last().is_none_or(|s: &Step| s.lod() != Some(d)) {
                    steps.push(Step::Lod(d));
                }
            }
        }
        if config.use_render_distance {
            let floor = config.min_render_distance.max(2);
            let mut d = wanted.render_distance;
            while d > floor {
                d = d.saturating_sub(2).max(floor);
                steps.push(Step::Render(d));
            }
        }
        if config.use_resolution {
            for scale in SCALE_STEPS {
                if scale < wanted.resolution_scale {
                    steps.push(Step::Scale(scale));
                }
            }
        }
        steps
    }

    /// The caps after the first `level` steps.
    fn caps_at(&self, level: u32, steps: &[Step]) -> Caps {
        let mut caps = Caps::default();
        for step in steps.iter().take(level as usize) {
            match *step {
                Step::Lod(d) => caps.lod_distance = Some(d),
                Step::Render(d) => caps.render_distance = Some(d),
                Step::Scale(s) => caps.resolution_scale = Some(s),
            }
        }
        caps
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Step {
    Lod(u32),
    Render(u32),
    Scale(u32),
}

impl Step {
    fn lod(self) -> Option<u32> {
        match self {
            Step::Lod(d) => Some(d),
            _ => None,
        }
    }
}

/// The value a setting actually takes: the player's own, held to the cap.
pub fn capped(wanted: u32, cap: Option<u32>) -> u32 {
    cap.map_or(wanted, |c| wanted.min(c))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn on() -> Config {
        Config {
            enabled: true,
            ..Config::default()
        }
    }

    const WANTED: Wanted = Wanted {
        render_distance: 12,
        lod_distance: 16,
        resolution_scale: 100,
    };

    /// Runs readings 5 s apart and returns the caps after the last one.
    fn run(g: &mut Governor, c: &Config, readings: &[u64]) -> Caps {
        let mut caps = Caps::default();
        for (i, mb) in readings.iter().enumerate() {
            caps = g.tick(c, WANTED, Some(*mb), i as f64 * CHECK_EVERY_SECS);
        }
        caps
    }

    #[test]
    fn it_does_nothing_when_off_or_when_the_system_does_not_say() {
        let mut g = Governor::new();
        assert!(!g.tick(&Config::default(), WANTED, Some(10), 0.0).any());
        assert!(!g.tick(&on(), WANTED, None, 5.0).any());
        assert_eq!(g.level(), 0);
    }

    #[test]
    fn plenty_of_memory_changes_nothing() {
        let mut g = Governor::new();
        assert!(!run(&mut g, &on(), &[2000; 20]).any());
    }

    #[test]
    fn short_memory_cuts_far_terrain_first() {
        let mut g = Governor::new();
        let caps = g.tick(&on(), WANTED, Some(450), 0.0);
        assert_eq!(caps.lod_distance, Some(8));
        assert_eq!(
            caps.render_distance, None,
            "render distance is untouched at first"
        );
    }

    #[test]
    fn it_steps_down_one_at_a_time_and_waits_for_a_step_to_show() {
        let mut g = Governor::new();
        let c = on();
        assert_eq!(g.tick(&c, WANTED, Some(450), 0.0).lod_distance, Some(8));
        // 5 s later still short, but the last step has not had its settle time.
        assert_eq!(g.tick(&c, WANTED, Some(450), 5.0).lod_distance, Some(8));
        assert_eq!(g.level(), 1);
        // 10 s after the first step: the next one.
        assert_eq!(g.tick(&c, WANTED, Some(450), 10.0).lod_distance, Some(4));
        assert_eq!(g.level(), 2);
    }

    #[test]
    fn far_terrain_goes_before_render_distance_and_render_distance_stops_at_the_floor() {
        let mut g = Governor::new();
        let c = on();
        let mut caps = Caps::default();
        for i in 0..40 {
            caps = g.tick(&c, WANTED, Some(450), i as f64 * 10.0);
        }
        assert_eq!(caps.lod_distance, Some(0));
        assert_eq!(
            caps.render_distance,
            Some(6),
            "never below the player's floor"
        );
        assert_eq!(caps.resolution_scale, None, "resolution is opt-in");
    }

    #[test]
    fn a_critical_reading_pulls_every_allowed_lever_at_once() {
        let mut g = Governor::new();
        let c = Config {
            use_resolution: true,
            ..on()
        };
        let caps = g.tick(&c, WANTED, Some(100), 0.0);
        assert_eq!(caps.lod_distance, Some(0));
        assert_eq!(caps.render_distance, Some(6));
        assert_eq!(caps.resolution_scale, Some(55));
    }

    #[test]
    fn quality_comes_back_slowly_and_only_after_a_steady_run_of_good_readings() {
        let mut g = Governor::new();
        let c = on();
        for i in 0..40 {
            g.tick(&c, WANTED, Some(450), i as f64 * 10.0);
        }
        let deep = g.level();
        assert!(deep > 3);
        // Five good readings are not enough.
        for i in 0..5 {
            g.tick(&c, WANTED, Some(2000), 500.0 + i as f64 * 5.0);
        }
        assert_eq!(g.level(), deep);
        // The sixth gives back exactly one step.
        g.tick(&c, WANTED, Some(2000), 530.0);
        assert_eq!(g.level(), deep - 1);
        // And it takes another full run for the next.
        g.tick(&c, WANTED, Some(2000), 535.0);
        assert_eq!(g.level(), deep - 1);
    }

    #[test]
    fn a_reading_hovering_between_the_lines_cannot_flap() {
        let mut g = Governor::new();
        let c = on();
        g.tick(&c, WANTED, Some(450), 0.0);
        let level = g.level();
        // Low is 500 and comfortable is 800: 600 is neither, so nothing moves, ever.
        for i in 1..200 {
            g.tick(&c, WANTED, Some(600), i as f64 * 5.0);
            assert_eq!(g.level(), level);
        }
    }

    #[test]
    fn one_bad_reading_in_a_good_run_restarts_the_count() {
        let mut g = Governor::new();
        let c = on();
        g.tick(&c, WANTED, Some(450), 0.0);
        for i in 0..5 {
            g.tick(&c, WANTED, Some(2000), 20.0 + i as f64 * 5.0);
        }
        g.tick(&c, WANTED, Some(600), 45.0);
        for i in 0..5 {
            g.tick(&c, WANTED, Some(2000), 50.0 + i as f64 * 5.0);
        }
        assert_eq!(
            g.level(),
            1,
            "five good readings after the dip are still not six"
        );
    }

    #[test]
    fn only_the_levers_the_player_allows_are_used() {
        let mut g = Governor::new();
        let c = Config {
            use_far_terrain: false,
            use_render_distance: false,
            use_resolution: true,
            ..on()
        };
        let caps = g.tick(&c, WANTED, Some(100), 0.0);
        assert_eq!(caps.lod_distance, None);
        assert_eq!(caps.render_distance, None);
        assert_eq!(caps.resolution_scale, Some(55));
        // With every lever off there is nothing to do at any pressure.
        let none = Config {
            use_far_terrain: false,
            use_render_distance: false,
            use_resolution: false,
            ..on()
        };
        assert!(!Governor::new().tick(&none, WANTED, Some(10), 0.0).any());
    }

    #[test]
    fn a_cap_never_raises_the_players_own_value() {
        // The player already chose a short render distance: the floor is not "a raise".
        let wanted = Wanted {
            render_distance: 4,
            lod_distance: 0,
            resolution_scale: 100,
        };
        let mut g = Governor::new();
        let caps = g.tick(&on(), wanted, Some(100), 0.0);
        assert_eq!(caps.render_distance, None);
        assert_eq!(caps.lod_distance, None);
        assert_eq!(capped(4, Some(6)), 4);
        assert_eq!(capped(12, Some(6)), 6);
        assert_eq!(capped(12, None), 12);
    }

    #[test]
    fn a_higher_sensitivity_acts_sooner() {
        for (early, relaxed) in [(Sensitivity::Early, Sensitivity::Relaxed)] {
            let mut a = Governor::new();
            let mut b = Governor::new();
            let (ca, cb) = (
                Config {
                    sensitivity: early,
                    ..on()
                },
                Config {
                    sensitivity: relaxed,
                    ..on()
                },
            );
            // 600 MB available: Early is below its line, Relaxed is not.
            assert!(a.tick(&ca, WANTED, Some(600), 0.0).any());
            assert!(!b.tick(&cb, WANTED, Some(600), 0.0).any());
        }
        for s in Sensitivity::ALL {
            assert!(s.critical_mb() < s.low_mb() && s.low_mb() < s.comfortable_mb());
        }
    }

    #[test]
    fn switching_it_off_lifts_everything_at_once() {
        let mut g = Governor::new();
        assert!(g.tick(&on(), WANTED, Some(100), 0.0).any());
        let off = Config::default();
        assert!(!g.tick(&off, WANTED, Some(100), 5.0).any());
        assert_eq!(g.level(), 0);
    }

    #[test]
    fn the_steps_for_a_player_with_nothing_to_cut_are_empty() {
        let wanted = Wanted {
            render_distance: 6,
            lod_distance: 0,
            resolution_scale: 50,
        };
        let mut g = Governor::new();
        let c = Config {
            use_resolution: true,
            ..on()
        };
        assert!(!g.tick(&c, wanted, Some(1), 0.0).any());
    }
}
