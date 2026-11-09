//! The touch controls editor (iMC Settings > Edit touch controls): the on-screen buttons drawn
//! exactly as they are in play, over the world, on a wide stage the player drags them around.
//! A panel on the right sets the size and opacity of the one picked, hides it or puts it back.
//! The arrangement is `settings.touch_layout`; the pure parts (the panel's places, the steps, the
//! file) are `horizon_client_input::touch_layout`. Nothing here reaches a server.
//!
//! Done keeps the arrangement. Cancel, and Back, put back the one the editor opened with.
use super::touch::{PAD_COUNT, faded, pad_base, pad_label, pad_slot};
use super::{Game, Screen};
use horizon_client::{
    hud::{HudBatch, rgba},
    text::Text,
    ui,
};
use horizon_client_input::touch_layout::{
    ControlLayout, Slot,
    editor::{self, Action},
};

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
}

/// A frame's colour for the picked button and for the others.
const FRAME_PICKED: u32 = 0xFFFF_FF55;
const FRAME: u32 = 0x60FF_FFFF;
const STAGE_TINT: u32 = 0x4000_0000;

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
        (0..PAD_COUNT).rev().find(|&i| {
            let r = self.editor_pad_rect(i, size);
            let (cx, cy) = self.cursor;
            cx >= r[0] && cx < r[0] + r[2] && cy >= r[1] && cy < r[1] + r[3]
        })
    }

    /// A pad's rectangle in GUI units, shown or not.
    fn editor_pad_rect(&self, i: usize, size: (f32, f32)) -> [f32; 4] {
        let slot = Slot {
            shown: true,
            ..self.settings.touch_layout.slot(pad_slot(i))
        };
        slot.place(
            pad_base(i, size, self.settings.imc.safe_margin_scale()),
            size,
        )
    }

    pub(super) fn draw_touch_editor(&mut self, batch: &mut HudBatch) {
        let size = (batch.width, batch.height);
        let atlas = &self.gui.atlas;
        let colour = |c: u32| {
            let [a, r, g, b] = c.to_be_bytes();
            rgba(r, g, b, a)
        };
        let Some(picked) = self.touch_editor.as_ref().map(|e| e.picked) else {
            return;
        };
        let stage = editor::stage_width(size);
        batch.fill(atlas, 0.0, 0.0, stage, size.1, colour(STAGE_TINT));
        batch.fill(
            atlas,
            stage,
            0.0,
            size.0 - stage,
            size.1,
            colour(0xC000_0000),
        );

        for i in 0..PAD_COUNT {
            let slot = self.settings.touch_layout.slot(pad_slot(i));
            let [x, y, w, h] = self.editor_pad_rect(i, size);
            // A hidden button is drawn faintly, outlined, so it can still be found.
            let opacity = if slot.shown { slot.opacity } else { 0.25 };
            batch.fill(atlas, x, y, w, h, faded(0x5000_0000, opacity));
            let label = pad_label(i);
            let tw = HudBatch::text_width(atlas, label);
            batch.text(
                atlas,
                label,
                x + (w - tw) / 2.0,
                y + (h - 8.0) / 2.0,
                faded(0xFFFF_FFFF, opacity),
                true,
            );
            let c = colour(if i == picked { FRAME_PICKED } else { FRAME });
            batch.fill(atlas, x - 1.0, y - 1.0, w + 2.0, 1.0, c);
            batch.fill(atlas, x - 1.0, y + h, w + 2.0, 1.0, c);
            batch.fill(atlas, x - 1.0, y, 1.0, h, c);
            batch.fill(atlas, x + w, y, 1.0, h, c);
        }

        // The heading and the picked button's numbers, at the top of the panel.
        let slot = self.settings.touch_layout.slot(pad_slot(picked));
        let name = Text::literal(pad_label(picked));
        let line = |t: &str| Text::literal(t);
        let head = line("Touch controls");
        let hx = stage + 8.0;
        batch.text_styled(atlas, &head, hx, 4.0, u32::MAX, true);
        let info = Text::literal(&format!(
            "{}  {}  {}{}",
            pad_label(picked),
            editor::percent(slot.scale),
            editor::percent(slot.opacity),
            if slot.shown { "" } else { "  hidden" }
        ));
        let _ = name;
        batch.text_styled(atlas, &info, hx, 4.0 + 12.0, 0xFFFF_FF55, true);

        for (action, [x, y, w, h]) in editor::panel(size) {
            let label = Text::literal(match action {
                Action::SmallerButton => "Size -",
                Action::BiggerButton => "Size +",
                Action::FainterButton => "Fade -",
                Action::SolidButton => "Fade +",
                Action::ToggleShown => {
                    if slot.shown {
                        "Hide"
                    } else {
                        "Show"
                    }
                }
                Action::ResetButton => "Reset button",
                Action::ResetAll => "Reset all",
                Action::Cancel => "Cancel",
                Action::Done => "Done",
            });
            let hover = ui::hovered(self.cursor, x, y, w, h);
            ui::button(batch, atlas, x, y, w, h, &label, true, hover);
        }
    }

    /// A press: a panel button, else the button under the finger, which is picked and held.
    pub(super) fn touch_editor_press(&mut self) {
        let size = self.gui_size();
        if let Some(action) = editor::action_at(size, self.cursor) {
            self.audio.play_button_click();
            self.touch_editor_act(action);
            return;
        }
        if self.cursor.0 >= editor::stage_width(size) {
            return;
        }
        if let Some(i) = self.editor_pad_at() {
            let r = self.editor_pad_rect(i, size);
            let grab = (self.cursor.0 - r[0], self.cursor.1 - r[1]);
            if let Some(e) = &mut self.touch_editor {
                e.picked = i;
                e.grab = Some(grab);
            }
        }
    }

    fn touch_editor_act(&mut self, action: Action) {
        let Some(picked) = self.touch_editor.as_ref().map(|e| e.picked) else {
            return;
        };
        let index = pad_slot(picked);
        match action {
            Action::Done => self.close_touch_editor(true),
            Action::Cancel => self.close_touch_editor(false),
            Action::ResetAll => self.settings.touch_layout.reset(),
            Action::ResetButton => self.settings.touch_layout.reset_slot(index),
            step => {
                let slot = editor::step(self.settings.touch_layout.slot(index), step);
                self.settings.touch_layout.slots[index] = slot;
            }
        }
    }

    /// The finger moved: the held button follows it, kept on the stage.
    pub(super) fn touch_editor_drag(&mut self) {
        let Some((picked, (gx, gy))) = self
            .touch_editor
            .as_ref()
            .and_then(|e| e.grab.map(|g| (e.picked, g)))
        else {
            return;
        };
        let size = self.gui_size();
        let index = pad_slot(picked);
        let slot = self.settings.touch_layout.slot(index);
        let base = pad_base(picked, size, self.settings.imc.safe_margin_scale());
        // The size the button has now, held where the finger took it.
        let placed = Slot {
            dx: 0.0,
            dy: 0.0,
            ..slot
        }
        .place(base, size);
        let target = [
            (self.cursor.0 - gx).clamp(0.0, editor::stage_width(size) - placed[2]),
            (self.cursor.1 - gy).clamp(0.0, size.1 - placed[3]),
            placed[2],
            placed[3],
        ];
        let moved = slot.moved_to(
            Slot {
                dx: 0.0,
                dy: 0.0,
                ..slot
            }
            .place(base, size),
            target,
            size,
        );
        self.settings.touch_layout.slots[index] = Slot {
            shown: slot.shown,
            ..moved
        };
    }

    pub(super) fn touch_editor_release(&mut self) {
        if let Some(e) = &mut self.touch_editor
            && e.grab.take().is_some()
        {
            self.settings.save(&Self::options_path());
        }
    }
}
