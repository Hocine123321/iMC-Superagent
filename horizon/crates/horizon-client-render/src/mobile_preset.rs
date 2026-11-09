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
    fn applying_twice_changes_nothing_more() {
        let once = mobile();
        let mut twice = mobile();
        apply(&mut twice);
        assert_eq!(once.render_distance, twice.render_distance);
        assert_eq!(once.max_fps, twice.max_fps);
        assert_eq!(once.horizon.battery, twice.horizon.battery);
    }
}
