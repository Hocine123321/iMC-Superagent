---
title: The title-screen crash was a stack overflow
summary: Why the app died right after "loading the title artwork", how it was measured, and what was changed.
---

# The crash after "loading the title artwork"

## What happened (measured on the owner's iPhone 12, iOS 27.2, via LiveContainer)

- `latest.log` ended at `Horizon: loading the title artwork`. No Rust crash report was written.
- `crash.txt` (written by `platform/ios/App/CrashReporter.m`) showed `SIGSEGV`, code 2, on the
  **main thread**, inside `pollster::block_on<Renderer::new>`, called from `loading_renderer`.
- The same report states the main thread's stack: **1008 KB**, low end `0x16d390000`. The fault
  address was `0x16d38fc80`, 896 bytes **below** it. That is a stack overflow.
- Memory was not the cause (142 to 175 MB used, 1.9 GB left).

## Why 1 MB was not enough (read from the shipped arm64 binary, build 20)

The prologues of the functions on the crash path reserve their whole frame up front. Reading them:

| Function (on the path in the backtrace) | Frame |
|---|---|
| `game::run_with` | 416 KB |
| `loading_screen::run_event_loop` | 268 KB (not on this path, but `run_with` calls it) |
| `App::about_to_wait` | 280 KB (it holds `Loading::finish`'s locals, 596 KB on their own) |
| `loading_renderer` | 104 KB |
| `block_on<Renderer::new>` | about 54 KB, the future itself is only 2344 bytes |

`run_with` stays on the stack for the whole run (`run_app` never returns on iOS), and so do the
frames above it. They add up to roughly 960 KB before `Renderer::new`'s own callees start. A desktop
has 8 MB, so this never showed there.

## What was ruled out

- **Running `Renderer::new` on a big-stack thread.** Tried. Its future is not `Send` (it holds a
  `dyn Error`, `Receiver`s and `RefCell`s), and winit's `Window::inner_size` needs the main thread.
- **Linking with a bigger `-stack_size`.** The app is started inside LiveContainer, which calls
  Horizon's `main` on its own thread, so Horizon's `LC_MAIN` may not be used. Not relied on.
- **A stack-switching crate.** Would change `Cargo.lock`, which is off limits.

## What was changed

Only code layout, no logic:

- `run_with` no longer contains the synchronous start path. It moved to `run_synchronous`, marked
  `#[inline(never)]`, so `run_with`'s frame no longer includes it.
- `Loading::finish`, `Loading::set_ui`, `poll_menu_resources` and `loading_renderer` are
  `#[inline(never)]`, so `about_to_wait` no longer carries `finish`'s locals.
- `CrashReporter` breadcrumbs name the step reached, so a future report says where it stopped.

## How to check it worked

Run the app and watch `latest.log`: after `loading the title artwork` it should go on to
`title renderer ready` (breadcrumb) and show the title screen. `crash.txt` records the main thread's
stack size and where any later fault landed. To measure the frames again, read the `sub sp` prologues
in the arm64 binary (see git history of this file for the script).

## What builds 22 to 25 taught (measured on the arm64 binaries)

Each fix moved the crash one step deeper, because the budget was only ever checked for the step that
had just failed. The real rule: **every frame from `run_with` down to the deepest callee of the
startup is on the 1008 KB main thread at once**, and a `Game` is held by value by every function
that receives it.

| build | worst chain (Rust frames) | died in |
|---|---|---|
| 22 (v1) | 1,232 KB | `Loading::finish` (596 KB frame beneath the renderer) |
| 24 (v2) | 914 KB measured, +95 KB system frames | `finish_game` (596 KB, under `start_game`) |
| 25 (v3) | 972 KB measured, +95 KB | `start_game` (280 KB) over `start_boxed` (268 KB) |

What did not work: a thread with a big stack (`Game` is not `Send`: it holds `Rc`, `Box<dyn Editor>`),
and switching stacks with `makecontext` (unavailable on iOS). `unsafe` is forbidden in this crate.

What does: `Game::new_boxed` builds the `Game` on the heap (`Box::new(Game { .. })`), `start_game`
returns `Option<Box<Game>>`, and `Game::new` (used by the tests) unboxes it. No function on the
startup path then holds a `Game` by value.

`tools/check_stack_budget.py` reads the frame sizes of the chain from the built binary and fails
the CI run when the total passes 760 KB, so a build that would crash is not published.
