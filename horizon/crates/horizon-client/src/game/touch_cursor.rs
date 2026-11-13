//! Cursor mode on the phone: the glue between `horizon_client_input::touch_cursor` (the pure
//! trackpad logic, unit tested) and the game.
//!
//! In a menu, with the cursor on, a finger does not point where it lands. It moves a drawn
//! pointer by how far it travels; a tap clicks where the pointer is. The pointer's actions go
//! through the same `touch_apply` path as plain touch, so every widget, slider and inventory slot
//! works with no per-screen code.
//!
//! The cursor is in use when [`touch_cursor::source_for`] says so: the player switched to it with
//! the button on the screen, or an inventory is open and "Cursor in inventory" is on. In the
//! world it plays no part: the world has its own controls, and the button there only chooses
//! what the next menu will use.
use super::event_loop::EventLoopCtl;
use super::touch::MenuButton;
use super::{Game, Screen};
use horizon_client::hud::HudBatch;
use horizon_client_input::touch::FingerId;
use horizon_client_input::touch_cursor::{self, Cursor, Source, switch};
use winit::event::TouchPhase;

/// The cursor's state in the game.
pub(super) struct CursorState {
    logic: Cursor,
    /// The player pressed the Cursor/Touch button: the cursor holds across screens.
    pub(super) switched: bool,
    /// The finger that went down on the switch button, and is not a pointer.
    switch_finger: Option<FingerId>,
    /// The finger holding the Shift button down, and not a pointer.
    shift_finger: Option<FingerId>,
    /// Whether the cursor was in use at the last look, to put the pointer in the middle when it
    /// starts and to let go of what it held when it stops.
    was_active: bool,
}

impl Default for CursorState {
    fn default() -> Self {
        CursorState {
            logic: Cursor::new((1.0, 1.0)),
            switched: false,
            switch_finger: None,
            shift_finger: None,
            was_active: false,
        }
    }
}

impl Game<'_> {
    /// The screens that are an inventory: the bag and what opens through it (chests, furnaces,
    /// crafting, villagers, horses) and creative.
    fn touch_in_inventory(&self) -> bool {
        self.title.is_none() && matches!(self.screen, Screen::Inventory | Screen::Creative)
    }

    /// How the cursor stands now. It only matters on a screen with a pointer.
    pub(super) fn cursor_source(&self) -> Source {
        if !self.pad_in_menu() || self.touch.calibrating.is_some() {
            return Source::Off;
        }
        touch_cursor::source_for(
            self.cursor_mode.switched,
            self.settings.imc.cursor_inventory,
            self.touch_in_inventory(),
        )
    }

    /// The cursor is the pointer for the finger now.
    pub(super) fn cursor_active(&self) -> bool {
        self.touch.seen && self.cursor_source().active()
    }

    /// Where the Cursor/Touch button is wanted: on every screen with a pointer, and in the
    /// world, so the player can choose before a menu opens. Not on the touch editor or
    /// calibration, which use the finger as the finger.
    fn cursor_switch_wanted(&self) -> bool {
        self.touch.seen
            && self.settings.imc.controls
            && self.touch.calibrating.is_none()
            && self.screen != Screen::TouchEditor
            && !self.prompt_open()
    }

    /// Where the Shift button is wanted: on the screens with slots (the inventory, chests,
    /// crafting, creative), whether the cursor or plain touch is in use.
    fn shift_wanted(&self) -> bool {
        self.touch.seen
            && self.settings.imc.controls
            && self.touch.calibrating.is_none()
            && self.touch_in_inventory()
            && !self.prompt_open()
    }

    /// Holds or lets go of the keyboard's Shift, as a finger on the button does. Every click,
    /// whichever way it is sent, then reads Shift as down (`has_shift_down`), so one tap on a
    /// stack is a quick move.
    fn shift_hold(&mut self, down: bool) {
        self.press_modifier_key(winit::keyboard::KeyCode::ShiftLeft, down);
    }

    /// The Shift button's finger: a press on it is kept from the pointer and holds Shift until
    /// the finger lifts, wherever it lifts. Returns whether the event was the button's.
    pub(super) fn shift_button_event(
        &mut self,
        id: FingerId,
        phase: TouchPhase,
        at: (f32, f32),
        size: (f32, f32),
    ) -> bool {
        match phase {
            TouchPhase::Started => {
                let on = self
                    .menu_button_rect(MenuButton::Shift, size)
                    .is_some_and(|r| horizon_client_input::touch_cursor::shift::contains(r, at));
                if self.shift_wanted() && on && self.cursor_mode.shift_finger.is_none() {
                    self.cursor_mode.shift_finger = Some(id);
                    self.shift_hold(true);
                    return true;
                }
                false
            }
            TouchPhase::Moved => self.cursor_mode.shift_finger == Some(id),
            TouchPhase::Ended | TouchPhase::Cancelled => {
                if self.cursor_mode.shift_finger != Some(id) {
                    return false;
                }
                self.cursor_mode.shift_finger = None;
                self.shift_hold(false);
                true
            }
        }
    }

    /// Keeps the cursor's start and end in step with the screen: a new use starts in the middle
    /// (or where the plain pointer last was), and ending one lets go of what it held.
    /// Returns the actions to apply.
    pub(super) fn cursor_follow(&mut self, size: (f32, f32)) -> Vec<horizon_client_input::touch::Action> {
        self.cursor_mode.logic.resize(size);
        self.cursor_mode.logic.speed = self.settings.imc.cursor_speed_scale();
        self.cursor_mode.logic.long_press_secs = self.settings.imc.cursor_hold_secs();
        self.cursor_mode.logic.allow_tap_drag = self.settings.imc.cursor_drag_grab;
        // The slop follows the screen, as plain touch does, so a thumb is the same size on any
        // phone; never under the cursor's own floor.
        self.cursor_mode.logic.slop = horizon_client_input::touch::slop_for(size)
            .max(horizon_client_input::touch_cursor::DEFAULT_SLOP);
        let active = self.cursor_active();
        let mut actions = Vec::new();
        if active && !self.cursor_mode.was_active {
            // The pointer starts where the plain pointer was, so the screen does not jump.
            self.cursor_mode.logic.place(self.touch.pointer);
        } else if !active && self.cursor_mode.was_active {
            actions = self.cursor_mode.logic.cancel_all();
        }
        self.cursor_mode.was_active = active;
        actions
    }

    /// A finger event while the cursor is in use. Returns `true` when the cursor took it.
    pub(super) fn cursor_event(
        &mut self,
        event_loop: &dyn EventLoopCtl,
        id: FingerId,
        phase: TouchPhase,
        at: (f32, f32),
        size: (f32, f32),
        now: f64,
    ) -> bool {
        let actions = self.cursor_follow(size);
        self.touch_apply(event_loop, actions);
        if !self.cursor_active() {
            return false;
        }
        let actions = match phase {
            TouchPhase::Started => self.cursor_mode.logic.down(id, at, now),
            TouchPhase::Moved => self.cursor_mode.logic.moved(id, at, now),
            TouchPhase::Ended => self.cursor_mode.logic.up(id, now, false),
            TouchPhase::Cancelled => self.cursor_mode.logic.up(id, now, true),
        };
        // Where the pointer is now, so the next screen's plain pointer starts there too.
        self.touch.pointer = self.cursor_mode.logic.position();
        self.touch_apply(event_loop, actions);
        true
    }

    /// Each frame: the right click of a finger held still, and the start or end of the cursor
    /// when the screen changed with no finger on it (an inventory opened by the Inv button).
    pub(super) fn cursor_frame(&mut self, event_loop: &dyn EventLoopCtl, now: f64) {
        let Some(size) = self
            .renderer
            .as_ref()
            .map(|r| (r.config.width as f32, r.config.height as f32))
        else {
            return;
        };
        let actions = self.cursor_follow(size);
        self.touch_apply(event_loop, actions);
        if self.cursor_active() {
            let actions = self.cursor_mode.logic.tick(now);
            self.touch_apply(event_loop, actions);
        }
    }

    /// Everything the cursor holds is let go (the app is going to the background).
    pub(super) fn cursor_release_all(&mut self, event_loop: &dyn EventLoopCtl) {
        let actions = self.cursor_mode.logic.cancel_all();
        self.touch_apply(event_loop, actions);
        self.cursor_mode.switch_finger = None;
        if self.cursor_mode.shift_finger.take().is_some() {
            self.shift_hold(false);
        }
        self.cursor_mode.was_active = false;
    }

    /// The switch button's finger: a press on the button is kept from the pointer, and
    /// switches the mode when it lifts on it. Returns whether the event was the button's.
    pub(super) fn cursor_switch_event(
        &mut self,
        id: FingerId,
        phase: TouchPhase,
        at: (f32, f32),
        size: (f32, f32),
    ) -> bool {
        // Where the player's arrangement puts it; hidden, it is not there to press.
        let Some(rect) = self.menu_button_rect(MenuButton::Cursor, size) else {
            return false;
        };
        let on_button = at.0 >= rect[0]
            && at.0 < rect[0] + rect[2]
            && at.1 >= rect[1]
            && at.1 < rect[1] + rect[3];
        match phase {
            TouchPhase::Started => {
                if self.cursor_switch_wanted() && on_button && self.cursor_mode.switch_finger.is_none() {
                    self.cursor_mode.switch_finger = Some(id);
                    return true;
                }
                false
            }
            TouchPhase::Moved => self.cursor_mode.switch_finger == Some(id),
            TouchPhase::Ended | TouchPhase::Cancelled => {
                if self.cursor_mode.switch_finger != Some(id) {
                    return false;
                }
                self.cursor_mode.switch_finger = None;
                if phase == TouchPhase::Ended && switch::fires(true, at, rect) {
                    self.cursor_mode.switched = !self.cursor_mode.switched;
                    // Switching from the middle of a screen starts the pointer where the plain
                    // one last was; the next frame's `cursor_follow` does that.
                }
                true
            }
        }
    }

    /// The pointer, and the Cursor/Touch button. Over everything, like the touch controls.
    pub(super) fn draw_touch_cursor(&self, batch: &mut HudBatch) {
        if self.touch.calibrating.is_some() {
            return;
        }
        let size = (batch.width, batch.height);
        let atlas = &self.gui.atlas;
        let layout = &self.settings.touch_layout;
        if self.cursor_switch_wanted()
            && let Some([x, y, w, h]) = self.menu_button_rect(MenuButton::Cursor, size)
        {
            let opacity = layout.slot(horizon_client_input::touch_layout::CURSOR_SLOT).opacity;
            let down = self.cursor_mode.switch_finger.is_some();
            let on = self.cursor_mode.switched;
            // A lit button says the cursor is the choice; the caption says what a tap does.
            let fill = if down {
                0xA0FF_FFFF
            } else if on {
                0x8030_90FF
            } else {
                0x7000_0000
            };
            batch.fill(atlas, x, y, w, h, super::touch::faded(fill, opacity));
            let label = switch::caption(on);
            let tw = HudBatch::text_width(atlas, label);
            batch.text(
                atlas,
                label,
                x + (w - tw) / 2.0,
                y + (h - 8.0) / 2.0,
                super::touch::faded(0xFFFF_FFFF, opacity),
                true,
            );
        }
        if self.shift_wanted()
            && let Some([x, y, w, h]) = self.menu_button_rect(MenuButton::Shift, size)
        {
            let opacity = layout.slot(horizon_client_input::touch_layout::SHIFT_SLOT).opacity;
            // Lit while held, so the player can see Shift is on.
            let fill = if self.cursor_mode.shift_finger.is_some() {
                0xA030_90FF
            } else {
                0x7000_0000
            };
            batch.fill(atlas, x, y, w, h, super::touch::faded(fill, opacity));
            let label = horizon_client_input::touch_cursor::shift::CAPTION;
            let tw = HudBatch::text_width(atlas, label);
            batch.text(
                atlas,
                label,
                x + (w - tw) / 2.0,
                y + (h - 8.0) / 2.0,
                super::touch::faded(0xFFFF_FFFF, opacity),
                true,
            );
        }
        if !self.cursor_active() {
            return;
        }
        // The same crosshair the controller uses in inventories, centred on the point a tap
        // would press. The logic's position is in physical pixels; the batch is in GUI units.
        use horizon_client::pad_cursor;
        let (px, py) = self.cursor_mode.logic.position();
        let s = batch.scale;
        let (left, top) = pad_cursor::origin((px / s, py / s));
        batch.sprite_scaled(
            &self.gui.atlas,
            pad_cursor::SPRITE,
            left,
            top,
            pad_cursor::DRAWN,
            pad_cursor::DRAWN,
            u32::MAX,
        );
    }
}
