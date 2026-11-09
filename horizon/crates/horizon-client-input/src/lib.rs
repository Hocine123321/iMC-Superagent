//! The client's input layer, below gameplay and screens: key bindings and their
//! names, toggle keys, mouse settings, controllers, the clipboard and window
//! options. horizon-client re-exports each module under its old path
//! (`horizon_client::keybinds`, ...).
#![forbid(unsafe_code)]
pub mod actions;
pub mod auto_performance;
pub mod clipboard;
pub mod gamepad;
pub mod gameplay_guide;
pub mod held;
pub mod imc_settings;
pub mod input;
pub mod interaction_input;
pub mod key_names;
pub mod keybinds;
pub mod keymapping;
pub mod modifiers;
pub mod mouse;
pub mod snap;
pub mod touch;
pub mod touch_calibration;
pub mod touch_extras;
pub mod touch_layout;
pub mod window;
