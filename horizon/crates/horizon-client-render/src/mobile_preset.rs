//! The "Mobile" preset (iMC Settings > Mobile preset): the engine's own Performance preset, plus
//! what only a phone needs. Like the PvP preset it only changes values; every one stays adjustable
//! afterwards, one by one.
//!
//! What it sets, and why:
//! - everything the Performance preset sets (render distance 8, simulation distance 6, no
//!   clouds, minimal particles, no entity shadows, no biome blend, no mipmaps), since a phone has
//!   a fraction of a desktop's memory and heat budget;
//! - **battery mode** on: it caps frames at 60 in a world and 30 in menus, and halves the
//!   automatic worker count (`Graphics::battery_limit`);
//! - **max FPS 60** and **vsync on**: a phone screen shows no more, and a frame it cannot show is
//!   heat for nothing;
//! - resolution scale 100, LOD off, no upscaling, no HDR, no frame generation: all already the
//!   defaults, set here so the preset also undoes a change made earlier;
//! - view bobbing off: the view swaying on a small, held screen makes some people ill.
//!
//! What it leaves alone, on purpose: smooth lighting (cheap, a large visual gain), the texture
//! budget and leaf culling (no phone data yet: milestone M6 measures them), the shader pack
//! (the port keeps shader packs off), and the iMC Settings page, whose Auto Performance block
//! keeps its own caps.

use crate::graphics::{self, FrameGeneration, Preset, Upscaling};
use crate::settings::Settings;

/// The frame cap the preset sets.
pub const MAX_FPS: u32 = 60;

/// The phone presets the iMC page offers, in the order its row steps through them.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    /// The one that was always there: Performance values, battery mode, 60 FPS.
    Mobile,
    /// For a low battery or a hot phone: nearer, 30 FPS, battery mode.
    BatterySaver,
    /// For a phone on the charger: Balanced values, 60 FPS, no battery mode.
    Smooth,
}

impl Kind {
    pub const ALL: [Kind; 3] = [Kind::Mobile, Kind::BatterySaver, Kind::Smooth];

    pub fn name(self) -> &'static str {
        match self {
            Kind::Mobile => "Mobile",
            Kind::BatterySaver => "Battery saver",
            Kind::Smooth => "Smooth",
        }
    }

    /// The next one, wrapping.
    pub fn next(self) -> Kind {
        let i = Kind::ALL.iter().position(|k| *k == self).unwrap_or(0);
        Kind::ALL[(i + 1) % Kind::ALL.len()]
    }
}

/// Turns a phone preset on.
pub fn apply_kind(kind: Kind, s: &mut Settings) {
    match kind {
        Kind::Mobile => apply(s),
        Kind::BatterySaver => {
            apply(s);
            s.render_distance = 6;
            s.simulation_distance = 5;
            s.max_fps = 30;
        }
        Kind::Smooth => {
            graphics::apply_preset(Preset::Balanced, s);
            s.max_fps = MAX_FPS;
            s.vsync = true;
            s.view_bobbing = false;
            let g = &mut s.horizon;
            g.battery = false;
            g.resolution_scale = 100;
            g.lod_distance = 0;
            g.upscaling = Upscaling::Native;
            g.frame_generation = FrameGeneration::Off;
            g.hdr = false;
        }
    }
}

/// Which phone preset the settings are exactly at now, or `None` once anything it sets has been
/// changed by hand. The page shows this, so a press that worked is visible and a preset that was
/// later edited stops claiming to be on.
pub fn current(s: &Settings) -> Option<Kind> {
    Kind::ALL.into_iter().find(|k| {
        let mut want = s.clone();
        apply_kind(*k, &mut want);
        s.render_distance == want.render_distance
            && s.simulation_distance == want.simulation_distance
            && s.max_fps == want.max_fps
            && s.vsync == want.vsync
            && s.view_bobbing == want.view_bobbing
            && s.clouds == want.clouds
            && s.particles == want.particles
            && s.horizon.battery == want.horizon.battery
            && s.horizon.preset == want.horizon.preset
    })
}

/// Turns the Mobile preset on.
pub fn apply(s: &mut Settings) {
    graphics::apply_preset(Preset::Performance, s);
    s.max_fps = MAX_FPS;
    s.vsync = true;
    s.view_bobbing = false;
    let g = &mut s.horizon;
    g.battery = true;
    g.resolution_scale = 100;
    g.lod_distance = 0;
    g.upscaling = Upscaling::Native;
    g.frame_generation = FrameGeneration::Off;
    g.hdr = false;
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mobile() -> Settings {
        let mut s = Settings::default();
        apply(&mut s);
        s
    }

    #[test]
    fn it_starts_from_the_performance_preset() {
        let s = mobile();
        assert_eq!(s.render_distance, 8);
        assert_eq!(s.simulation_distance, 6);
        assert_eq!(s.clouds, "false");
        assert_eq!(s.particles, 2);
        assert!(!s.entity_shadows);
        assert_eq!(s.mipmap_levels, 0);
        assert_eq!(s.horizon.preset, Preset::Performance);
    }

    #[test]
    fn it_adds_what_a_phone_needs() {
        let s = mobile();
        assert!(s.horizon.battery);
        assert_eq!(s.max_fps, 60);
        assert!(s.vsync);
        assert!(!s.view_bobbing);
    }

    #[test]
    fn it_undoes_a_heavy_choice_made_before() {
        let mut s = Settings::default();
        s.horizon.resolution_scale = 150;
        s.horizon.lod_distance = 512;
        s.horizon.upscaling = Upscaling::Quality;
        s.horizon.frame_generation = FrameGeneration::Fsr31;
        s.horizon.hdr = true;
        s.render_distance = 32;
        s.max_fps = 260;
        apply(&mut s);
        assert_eq!(s.horizon.resolution_scale, 100);
        assert_eq!(s.horizon.lod_distance, 0);
        assert_eq!(s.horizon.upscaling, Upscaling::Native);
        assert_eq!(s.horizon.frame_generation, FrameGeneration::Off);
        assert!(!s.horizon.hdr);
        assert_eq!(s.render_distance, 8);
        assert_eq!(s.max_fps, 60);
    }

    #[test]
    fn it_leaves_alone_what_it_has_no_data_for() {
        let mut s = Settings::default();
        s.smooth_lighting = true;
        s.horizon.texture_budget_mib = 1536;
        s.horizon.shader_pack = "somepack".into();
        s.fov = 95.0;
        s.sensitivity = 0.8;
        s.gui_scale = 3;
        apply(&mut s);
        assert!(s.smooth_lighting);
        assert_eq!(s.horizon.texture_budget_mib, 1536);
        assert_eq!(s.horizon.shader_pack, "somepack");
        assert_eq!(s.fov, 95.0);
        assert_eq!(s.sensitivity, 0.8);
        assert_eq!(s.gui_scale, 3);
    }

    #[test]
    fn it_leaves_the_imc_settings_alone() {
        let mut s = Settings::default();
        s.imc.auto_sprint = true;
        s.imc.grey_unused = true;
        let before = s.imc.clone();
        apply(&mut s);
        assert_eq!(s.imc, before);
    }

    #[test]
    fn every_phone_preset_reads_back_as_itself_and_no_two_are_alike() {
        for kind in Kind::ALL {
            let mut s = Settings::default();
            apply_kind(kind, &mut s);
            assert_eq!(current(&s), Some(kind), "{kind:?}");
        }
        let (mut a, mut b) = (Settings::default(), Settings::default());
        apply_kind(Kind::Mobile, &mut a);
        apply_kind(Kind::BatterySaver, &mut b);
        assert_ne!(a.render_distance, b.render_distance);
        assert_ne!(a.max_fps, b.max_fps);
    }

    #[test]
    fn a_change_by_hand_stops_the_preset_claiming_to_be_on() {
        let mut s = Settings::default();
        assert_eq!(current(&s), None, "a fresh install matches none");
        apply_kind(Kind::Mobile, &mut s);
        assert_eq!(current(&s), Some(Kind::Mobile));
        s.render_distance = 10;
        assert_eq!(current(&s), None);
    }

    #[test]
    fn stepping_visits_all_three_and_wraps() {
        let mut k = Kind::Mobile;
        let mut seen = vec![k];
        for _ in 0..3 {
            k = k.next();
            seen.push(k);
        }
        assert_eq!(seen, vec![Kind::Mobile, Kind::BatterySaver, Kind::Smooth, Kind::Mobile]);
    }

    #[test]
    fn the_battery_saver_is_lighter_than_mobile_and_smooth_is_heavier() {
        let get = |k| {
            let mut s = Settings::default();
            apply_kind(k, &mut s);
            s
        };
        let (m, b, sm) = (get(Kind::Mobile), get(Kind::BatterySaver), get(Kind::Smooth));
        assert!(b.render_distance < m.render_distance && m.render_distance < sm.render_distance);
        assert!(b.max_fps < m.max_fps);
        assert!(b.horizon.battery && m.horizon.battery && !sm.horizon.battery);
    }

    #[test]
    fn applying_twice_changes_nothing_more() {
        let once = mobile();
        let mut twice = mobile();
        apply(&mut twice);
        assert_eq!(once.render_distance, twice.render_distance);
        assert_eq!(once.max_fps, twice.max_fps);
        assert_eq!(once.horizon.battery, twice.horizon.battery);
    }
}
