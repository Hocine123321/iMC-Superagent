//! iMC Settings > Calibrate touch: five targets the player taps, from which a stretch and a shift
//! are fitted (`horizon_client_input::touch_calibration`) and applied to every touch after that.
//!
//! It is a layer over whatever is on screen, not a screen of its own: while it runs
//! (`TouchState::calibrating`), `touch_event` hands every finger here and returns, so nothing
//! behind it hears of the taps. The overlay is drawn by `draw_touch_controls`.
use super::touch::Calibrating;
use super::Game;
use horizon_client::{hud::HudBatch, text::Text, ui};
use horizon_client_input::touch::to_surface;
use horizon_client_input::touch_calibration::{Calibration, TARGETS, target};
use winit::event::TouchPhase;

/// The two buttons as `[x, y, w, h]` fractions of the screen. At the bottom centre, where a touch
/// is least off, and wide, because the taps are not corrected yet.
const CANCEL: [f32; 4] = [0.28, 0.80, 0.20, 0.12];
const RESET: [f32; 4] = [0.52, 0.80, 0.20, 0.12];

fn scaled(f: [f32; 4], size: (f32, f32)) -> [f32; 4] {
    [f[0] * size.0, f[1] * size.1, f[2] * size.0, f[3] * size.1]
}

fn inside(r: [f32; 4], p: (f32, f32)) -> bool {
    p.0 >= r[0] && p.0 < r[0] + r[2] && p.1 >= r[1] && p.1 < r[1] + r[3]
}

impl Game<'_> {
    /// Starts a run over whatever is on screen. The old correction is switched off while it runs,
    /// so the taps are measured against the window as it is, not against the last fit.
    pub(super) fn open_touch_calibration(&mut self) {
        self.touch.seen = true;
        self.touch.calibrating = Some(Calibrating::default());
    }

    /// One finger while calibrating. `raw` is the window's report, uncorrected and unshifted.
    pub(super) fn touch_calibration_event(
        &mut self,
        phase: TouchPhase,
        raw: (f32, f32),
        size: (f32, f32),
    ) {
        // A tap counts when the finger goes down; Cancel and Reset fire on lift like any button,
        // so a slip off them cancels nothing.
        let (safe_origin, safe_size) = self.touch_safe_area();
        let at = to_surface(raw, safe_origin, safe_size, size);
        let Some(run) = self.touch.calibrating.as_mut() else {
            return;
        };
        match phase {
            TouchPhase::Started => {
                if inside(scaled(CANCEL, size), at) || inside(scaled(RESET, size), at) {
                    return;
                }
                if run.failed {
                    // The next tap after a refused run starts over.
                    *run = Calibrating::default();
                }
                let i = run.samples.len();
                run.samples.push((at, target(i, size)));
                log::info!(
                    "touch calibration: target {} at ({:.0}, {:.0}), finger reported ({:.0}, {:.0})",
                    i + 1,
                    target(i, size).0,
                    target(i, size).1,
                    at.0,
                    at.1
                );
                if run.samples.len() == TARGETS.len() {
                    self.finish_touch_calibration(size);
                }
            }
            TouchPhase::Ended => {
                if inside(scaled(CANCEL, size), at) {
                    self.touch.calibrating = None;
                } else if inside(scaled(RESET, size), at) {
                    self.settings.touch_calibration = Calibration::IDENTITY;
                    self.settings.save(&Self::options_path());
                    self.touch.calibrating = None;
                }
            }
            _ => {}
        }
    }

    /// All targets tapped: fit, keep and save, or refuse and say so.
    fn finish_touch_calibration(&mut self, size: (f32, f32)) {
        let Some(run) = self.touch.calibrating.as_mut() else {
            return;
        };
        match Calibration::fit(&run.samples, size) {
            Some(fitted) => {
                log::info!(
                    "touch calibration: stretch x {:.4} y {:.4}, shift x {:.1} y {:.1} px",
                    fitted.sx,
                    fitted.sy,
                    fitted.ox,
                    fitted.oy
                );
                self.settings.touch_calibration = fitted;
                self.settings.save(&Self::options_path());
                self.touch.calibrating = None;
            }
            None => {
                log::warn!("touch calibration: the taps did not fit; run refused");
                run.failed = true;
            }
        }
    }

    /// The overlay, over everything: a dark layer, the next target, how far along, two buttons.
    pub(super) fn draw_touch_calibration(&self, batch: &mut HudBatch) {
        let Some(run) = self.touch.calibrating.as_ref() else {
            return;
        };
        let atlas = &self.gui.atlas;
        let size = (batch.width, batch.height);
        batch.fill(atlas, 0.0, 0.0, size.0, size.1, 0xE000_0000);

        if !run.failed {
            // Every target, the tapped ones dim, the next one bright with a cross.
            for i in 0..TARGETS.len() {
                let (x, y) = target(i, size);
                let next = i == run.samples.len();
                let colour = if next {
                    0xFFFF_FF55
                } else if i < run.samples.len() {
                    0x4055_FF55
                } else {
                    0x40FF_FFFF
                };
                let r = if next { 6.0 } else { 3.0 };
                batch.fill(atlas, x - r, y - 0.5, r * 2.0, 1.0, colour);
                batch.fill(atlas, x - 0.5, y - r, 1.0, r * 2.0, colour);
                if next {
                    batch.fill(atlas, x - 1.5, y - 1.5, 3.0, 3.0, colour);
                }
            }
        }
        let head = if run.failed {
            "That did not fit. Tap the targets again, as close to the cross as you can."
        } else {
            "Tap the cross exactly, with the tip of your finger"
        };
        let count = format!("{} / {}", run.samples.len().min(TARGETS.len()), TARGETS.len());
        let tw = HudBatch::text_width(atlas, head);
        batch.text(atlas, head, (size.0 - tw) / 2.0, size.1 * 0.40, 0xFFFF_FFFF, true);
        let cw = HudBatch::text_width(atlas, &count);
        batch.text(atlas, &count, (size.0 - cw) / 2.0, size.1 * 0.40 + 14.0, 0xFFFF_FF55, true);

        for (frac, label) in [(CANCEL, "Cancel"), (RESET, "Reset to none")] {
            let [x, y, w, h] = scaled(frac, size);
            ui::button(batch, atlas, x, y, w, h, &Text::literal(label), true, false);
        }
    }
}
