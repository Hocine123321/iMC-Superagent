//! The touch controls editor (iMC Settings > Edit touch controls): the on-screen buttons drawn
//! exactly as they are in play, over the world, on a wide stage the player drags them around.
//! A panel on the right sets the size and opacity of the one picked, hides it or puts it back.
//! The arrangement is `settings.touch_layout`; the pure parts (the panel's places, the steps, the
//! file) are `horizon_client_input::touch_layout`. Nothing here reaches a server.
//!
//! Done keeps the arrangement. Cancel, and Back, put back the one the editor opened with.
use super::touch::{PadKind, faded};
use super::{Game, Screen};
use horizon_client::{
    hud::{HudBatch, rgba},
    text::Text,
    ui,
};
use horizon_client_input::touch_editor_tools::{
    self as tools, Guide,
    panel2::{self, Control},
};
use horizon_client_input::touch_layout::{ControlLayout, Slot};

/// What the editor holds while it is open.
pub(super) struct TouchEditor {
    /// The arrangement when the editor opened, for Cancel.
    before: ControlLayout,
    /// The button picked, as an index into the pads.
    picked: usize,
    /// While a finger drags the picked button: where in the button it took hold, in GUI units.
    grab: Option<(f32, f32)>,
    /// Opened from iMC Settings: Done and Cancel go back there.
    from_options: bool,
    /// The panel is open; folded, it leaves a tab and the stage gets the screen.
    panel_open: bool,
    /// Snapping to the grid (edges and other buttons always pull).
    snap_grid: bool,
    /// The slider a finger is dragging, if any.
    slider: Option<Control>,
    /// Which layout the list is on, an index into `Presets::names`.
    preset: usize,
    /// The lines the last snap landed on, drawn while the button is held.
    guides: Vec<Guide>,
}

/// A frame's colour for the picked button and for the others.
const FRAME_PICKED: u32 = 0xFFFF_FF55;
const FRAME: u32 = 0x60FF_FFFF;
/// A button that overlaps another or leaves the safe area.
const FRAME_PROBLEM: u32 = 0xFFFF_4040;
const STAGE_TINT: u32 = 0x4000_0000;

/// A value as the percentage the panel shows.
fn percent(v: f32) -> String {
    format!("{}%", (v * 100.0).round() as i32)
}

impl Game<'_> {
    /// Opens the editor over the game. It needs a world: the buttons are drawn over the real
    /// view, which is the preview.
    pub(super) fn open_touch_editor(&mut self, from_options: bool) {
        if self.player.is_none() || self.title.is_some() {
            return;
        }
        self.keys.clear();
        // The buttons are drawn from the first touch; the editor shows them whatever came first.
        self.touch.seen = true;
        self.touch_editor = Some(TouchEditor {
            before: self.settings.touch_layout.clone(),
            picked: 0,
            grab: None,
            from_options,
            panel_open: true,
            snap_grid: true,
            slider: None,
            preset: 0,
            guides: Vec::new(),
        });
        self.screen = Screen::TouchEditor;
        self.capture(false);
    }

    /// Leaves the editor: `keep` is Done, anything else puts the opening arrangement back.
    pub(super) fn close_touch_editor(&mut self, keep: bool) {
        let Some(editor) = self.touch_editor.take() else {
            self.screen = Screen::Playing;
            return;
        };
        if !keep {
            self.settings.touch_layout = editor.before;
        }
        self.settings.save(&Self::options_path());
        if editor.from_options {
            self.open_options_at(false, horizon_client::options_ui::Page::Imc);
        } else {
            self.screen = Screen::Playing;
            self.capture(true);
        }
    }

    /// The button under the cursor, the topmost first, hidden ones included: a hidden button is
    /// shown faintly on the stage so it can be picked and shown again.
    fn editor_pad_at(&self) -> Option<usize> {
        let size = self.gui_size();
        let kinds = self.pad_kinds();
        (0..kinds.len()).rev().find(|&i| {
            let r = self.editor_pad_rect(kinds[i], size);
            let (cx, cy) = self.cursor;
            cx >= r[0] && cx < r[0] + r[2] && cy >= r[1] && cy < r[1] + r[3]
        })
    }

    /// A pad's rectangle in GUI units, shown or not.
    fn editor_pad_rect(&self, kind: PadKind, size: (f32, f32)) -> [f32; 4] {
        let slot = Slot {
            shown: true,
            ..self.settings.touch_layout.slot(kind.slot())
        };
        slot.place(kind.base(size, self.settings.imc.safe_margin_scale()), size)
    }

    /// The button the editor has picked, or the first if the list got shorter under it.
    fn editor_kind(&self, picked: usize) -> PadKind {
        let kinds = self.pad_kinds();
        kinds.get(picked).or(kinds.first()).copied().unwrap_or(PadKind::Fixed(0))
    }

    /// The safe area for the problem check, the same margins touch lays the buttons out in.
    fn editor_safe(&self, size: (f32, f32)) -> [f32; 4] {
        let m = self.settings.imc.safe_margin_scale();
        tools::safe_area(size, super::touch::SAFE_SIDE * m, super::touch::SAFE_TOP * m, super::touch::SAFE_BOTTOM * m)
    }

    /// Where every button stands now, `None` for a hidden one.
    fn editor_rects(&self, size: (f32, f32)) -> Vec<Option<[f32; 4]>> {
        self.pad_kinds()
            .into_iter()
            .map(|k| {
                self.settings
                    .touch_layout
                    .slot(k.slot())
                    .shown
                    .then(|| self.editor_pad_rect(k, size))
            })
            .collect()
    }

    pub(super) fn draw_touch_editor(&mut self, batch: &mut HudBatch) {
        let size = (batch.width, batch.height);
        let atlas = &self.gui.atlas;
        let colour = |c: u32| {
            let [a, r, g, b] = c.to_be_bytes();
            rgba(r, g, b, a)
        };
        let Some((picked, open, snap_grid, preset, guides)) = self.touch_editor.as_ref().map(|e| {
            (e.picked, e.panel_open, e.snap_grid, e.preset, e.guides.clone())
        }) else {
            return;
        };
        let stage = panel2::stage_width(size, open);
        batch.fill(atlas, 0.0, 0.0, stage, size.1, colour(STAGE_TINT));
        // The safe area, so a button's place against the notch and the home bar is visible.
        let safe = self.editor_safe(size);
        let edge = colour(0x40FF_FFFF);
        batch.fill(atlas, safe[0], safe[1], safe[2], 1.0, edge);
        batch.fill(atlas, safe[0], safe[1] + safe[3], safe[2], 1.0, edge);
        batch.fill(atlas, safe[0], safe[1], 1.0, safe[3], edge);
        batch.fill(atlas, safe[0] + safe[2], safe[1], 1.0, safe[3], edge);

        let flagged: Vec<usize> = tools::problems(&self.editor_rects(size), safe)
            .into_iter()
            .map(|(i, _)| i)
            .collect();
        for (i, kind) in self.pad_kinds().into_iter().enumerate() {
            let slot = self.settings.touch_layout.slot(kind.slot());
            let [x, y, w, h] = self.editor_pad_rect(kind, size);
            // A hidden button is drawn faintly, outlined, so it can still be found.
            let opacity = if slot.shown { slot.opacity } else { 0.25 };
            batch.fill(atlas, x, y, w, h, faded(0x5000_0000, opacity));
            let label = kind.label();
            let tw = HudBatch::text_width(atlas, label);
            batch.text(
                atlas,
                label,
                x + (w - tw) / 2.0,
                y + (h - 8.0) / 2.0,
                faded(0xFFFF_FFFF, opacity),
                true,
            );
            // Red for a button that overlaps another or leaves the safe area, yellow for the
            // one picked, white for the rest.
            let c = colour(if flagged.contains(&i) {
                FRAME_PROBLEM
            } else if i == picked {
                FRAME_PICKED
            } else {
                FRAME
            });
            batch.fill(atlas, x - 1.0, y - 1.0, w + 2.0, 1.0, c);
            batch.fill(atlas, x - 1.0, y + h, w + 2.0, 1.0, c);
            batch.fill(atlas, x - 1.0, y, 1.0, h, c);
            batch.fill(atlas, x + w, y, 1.0, h, c);
            if i == picked && flagged.contains(&i) {
                let c = colour(FRAME_PICKED);
                batch.fill(atlas, x + 1.0, y + 1.0, w - 2.0, 1.0, c);
            }
        }
        // The lines a snap landed on, while the button is held.
        let guide = colour(0xC055_FFFF);
        for g in &guides {
            match *g {
                Guide::Vertical(x) => batch.fill(atlas, x, 0.0, 1.0, size.1, guide),
                Guide::Horizontal(y) => batch.fill(atlas, 0.0, y, stage, 1.0, guide),
            }
        }

        // The panel: a strip down the edge with the fold tab, and when open the controls.
        let picked_kind = self.editor_kind(picked);
        let slot = self.settings.touch_layout.slot(picked_kind.slot());
        let names = self.settings.touch_presets.names();
        let preset_name = names.get(preset).cloned().unwrap_or_default();
        let left = size.0 - panel2::width(open);
        batch.fill(atlas, left, 0.0, size.0 - left, size.1, colour(0xC000_0000));
        for (control, [x, y, w, h]) in panel2::layout(size, open) {
            let hover = ui::hovered(self.cursor, x, y, w, h);
            let text = |t: &str| Text::literal(t);
            match control {
                Control::Fold => {
                    let label = text(if open { ">" } else { "<" });
                    ui::button(batch, atlas, x, y, w, h.min(40.0), &label, true, hover);
                }
                Control::SizeSlider | Control::FadeSlider => {
                    let (frac, label) = if control == Control::SizeSlider {
                        (
                            panel2::scale_fraction(slot.scale),
                            format!("Size {}", percent(slot.scale)),
                        )
                    } else {
                        (
                            panel2::opacity_fraction(slot.opacity),
                            format!("Fade {}", percent(slot.opacity)),
                        )
                    };
                    batch.fill(atlas, x, y, w, h, colour(0xFF30_3030));
                    batch.fill(atlas, x, y, w * frac, h, colour(0xFF4A_7A4A));
                    let hx = x + (w - 4.0) * frac;
                    batch.fill(atlas, hx, y, 4.0, h, colour(0xFFFF_FFFF));
                    let tw = HudBatch::text_width(atlas, &label);
                    batch.text(atlas, &label, x + (w - tw) / 2.0, y + (h - 8.0) / 2.0, u32::MAX, true);
                }
                _ => {
                    let label = match control {
                        Control::ToggleShown => if slot.shown { "Hide" } else { "Show" }.to_owned(),
                        Control::ToggleSnap => format!("Grid {}", if snap_grid { "on" } else { "off" }),
                        Control::NextPreset => preset_name.clone(),
                        Control::SavePreset => "Save".to_owned(),
                        Control::DeletePreset => "Delete".to_owned(),
                        Control::ResetButton => "Reset".to_owned(),
                        Control::ResetAll => "Reset all".to_owned(),
                        Control::Cancel => "Cancel".to_owned(),
                        _ => "Done".to_owned(),
                    };
                    // Delete is only live on a saved layout, never on a built in one.
                    let live = control != Control::DeletePreset
                        || !tools::BUILT_IN.contains(&preset_name.as_str());
                    ui::button(batch, atlas, x, y, w, h, &text(&label), live, hover && live);
                }
            }
        }
        if open {
            let hx = left + panel2::TAB_W + 4.0;
            batch.text_styled(atlas, &Text::literal("Touch controls"), hx, 4.0, u32::MAX, true);
            let info = format!("{}{}", picked_kind.label(), if slot.shown { "" } else { "  hidden" });
            batch.text_styled(atlas, &Text::literal(&info), hx, 4.0 + 12.0, 0xFFFF_FF55, true);
        }
    }

    /// A press: a panel control, else the button under the finger, which is picked and held.
    pub(super) fn touch_editor_press(&mut self) {
        let size = self.gui_size();
        let open = self.touch_editor.as_ref().is_some_and(|e| e.panel_open);
        if let Some(control) = panel2::control_at(size, open, self.cursor) {
            self.audio.play_button_click();
            self.touch_editor_act(control, size);
            return;
        }
        if self.cursor.0 >= panel2::stage_width(size, open) {
            return;
        }
        if let Some(i) = self.editor_pad_at() {
            let r = self.editor_pad_rect(self.editor_kind(i), size);
            let grab = (self.cursor.0 - r[0], self.cursor.1 - r[1]);
            if let Some(e) = &mut self.touch_editor {
                e.picked = i;
                e.grab = Some(grab);
            }
        }
    }

    /// The track of a slider, for a finger that is dragging it.
    fn editor_track(&self, control: Control, size: (f32, f32)) -> Option<[f32; 4]> {
        panel2::layout(size, true)
            .into_iter()
            .find_map(|(c, r)| (c == control).then_some(r))
    }

    /// Sets the picked button's size or fade from where the finger is on the slider.
    fn editor_slide(&mut self, control: Control, size: (f32, f32)) {
        let Some(track) = self.editor_track(control, size) else {
            return;
        };
        let Some(picked) = self.touch_editor.as_ref().map(|e| e.picked) else {
            return;
        };
        let index = self.editor_kind(picked).slot();
        let f = panel2::track_fraction(track, self.cursor.0);
        let mut slot = self.settings.touch_layout.slot(index);
        if control == Control::SizeSlider {
            slot.scale = panel2::scale_at(f);
        } else {
            slot.opacity = panel2::opacity_at(f);
        }
        self.settings.touch_layout.slots[index] = slot.clamped();
    }

    fn touch_editor_act(&mut self, control: Control, size: (f32, f32)) {
        let Some(picked) = self.touch_editor.as_ref().map(|e| e.picked) else {
            return;
        };
        let index = self.editor_kind(picked).slot();
        let names = self.settings.touch_presets.names();
        match control {
            Control::Fold => {
                if let Some(e) = &mut self.touch_editor {
                    e.panel_open = !e.panel_open;
                }
            }
            Control::SizeSlider | Control::FadeSlider => {
                if let Some(e) = &mut self.touch_editor {
                    e.slider = Some(control);
                }
                self.editor_slide(control, size);
            }
            Control::ToggleShown => {
                let mut s = self.settings.touch_layout.slot(index);
                s.shown = !s.shown;
                self.settings.touch_layout.slots[index] = s;
            }
            Control::ToggleSnap => {
                if let Some(e) = &mut self.touch_editor {
                    e.snap_grid = !e.snap_grid;
                }
            }
            Control::NextPreset => {
                // Stepping to a layout puts it on the screen at once; Cancel undoes it.
                let next = self
                    .touch_editor
                    .as_ref()
                    .map_or(0, |e| (e.preset + 1) % names.len().max(1));
                if let Some(e) = &mut self.touch_editor {
                    e.preset = next;
                }
                if let Some(layout) = names
                    .get(next)
                    .and_then(|n| self.settings.touch_presets.get(n))
                {
                    self.settings.touch_layout = layout;
                }
            }
            Control::SavePreset => {
                // A new layout gets the next free "Layout N"; a saved one is kept under its name.
                let current = names
                    .get(self.touch_editor.as_ref().map_or(0, |e| e.preset))
                    .cloned()
                    .unwrap_or_default();
                let name = if tools::BUILT_IN.contains(&current.as_str()) {
                    (1..=tools::MAX_SAVED + 1)
                        .map(|n| format!("Layout {n}"))
                        .find(|n| !names.contains(n))
                        .unwrap_or_else(|| "Layout".to_owned())
                } else {
                    current
                };
                let layout = self.settings.touch_layout.clone();
                if self.settings.touch_presets.save(&name, &layout) {
                    let at = self
                        .settings
                        .touch_presets
                        .names()
                        .iter()
                        .position(|n| *n == name)
                        .unwrap_or(0);
                    if let Some(e) = &mut self.touch_editor {
                        e.preset = at;
                    }
                    self.settings.save(&Self::options_path());
                }
            }
            Control::DeletePreset => {
                let current = names
                    .get(self.touch_editor.as_ref().map_or(0, |e| e.preset))
                    .cloned()
                    .unwrap_or_default();
                if self.settings.touch_presets.delete(&current) {
                    if let Some(e) = &mut self.touch_editor {
                        e.preset = 0;
                    }
                    self.settings.save(&Self::options_path());
                }
            }
            Control::Done => self.close_touch_editor(true),
            Control::Cancel => self.close_touch_editor(false),
            Control::ResetAll => self.settings.touch_layout.reset(),
            Control::ResetButton => self.settings.touch_layout.reset_slot(index),
        }
    }

    /// The finger moved: a slider follows it, else the held button, snapped and kept on the stage.
    pub(super) fn touch_editor_drag(&mut self) {
        let size = self.gui_size();
        if let Some(control) = self.touch_editor.as_ref().and_then(|e| e.slider) {
            self.editor_slide(control, size);
            return;
        }
        let Some((picked, (gx, gy), open, grid)) = self
            .touch_editor
            .as_ref()
            .and_then(|e| e.grab.map(|g| (e.picked, g, e.panel_open, e.snap_grid)))
        else {
            return;
        };
        let kind = self.editor_kind(picked);
        let index = kind.slot();
        let slot = self.settings.touch_layout.slot(index);
        let base = kind.base(size, self.settings.imc.safe_margin_scale());
        // The size the button has now, held where the finger took it.
        let centred = Slot {
            dx: 0.0,
            dy: 0.0,
            ..slot
        }
        .place(base, size);
        let stage = panel2::stage_width(size, open);
        let target = [
            (self.cursor.0 - gx).clamp(0.0, stage - centred[2]),
            (self.cursor.1 - gy).clamp(0.0, size.1 - centred[3]),
            centred[2],
            centred[3],
        ];
        // Snap to the screen, the grid and the other buttons that show.
        let others: Vec<[f32; 4]> = self
            .editor_rects(size)
            .into_iter()
            .enumerate()
            .filter(|(i, _)| *i != picked)
            .filter_map(|(_, r)| r)
            .collect();
        let snapped = tools::snap(target, &others, (stage, size.1), grid);
        let moved = slot.moved_to(centred, snapped.rect, size);
        self.settings.touch_layout.slots[index] = Slot {
            shown: slot.shown,
            ..moved
        };
        if let Some(e) = &mut self.touch_editor {
            e.guides = snapped.guides;
        }
    }

    pub(super) fn touch_editor_release(&mut self) {
        if let Some(e) = &mut self.touch_editor {
            e.guides.clear();
            let slid = e.slider.take().is_some();
            if e.grab.take().is_some() || slid {
                self.settings.save(&Self::options_path());
            }
        }
    }
}
