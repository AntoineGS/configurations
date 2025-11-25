# Keyball 44 ZMK Configuration Guide

This document describes the ZMK configuration for the Keyball 44, migrated from a Piantor Pro QMK setup.

## Features

### Timeless Homerow Mods

This configuration implements "timeless homerow mods" based on [urob's ZMK config](https://github.com/urob/zmk-config#timeless-homerow-mods), making home row modifiers largely timing-independent.

**Key improvements over traditional home row mods:**

1. **Positional hold-tap**: Left-hand mods only activate when pressing keys on the right side (and vice versa)
   - Eliminates false positives from same-hand rolls
   - Uses `hold-trigger-on-release` to allow combining multiple modifiers on one hand

2. **Require-prior-idle** (150ms): After typing a regular key, home row mods immediately resolve as taps
   - Eliminates the perception of typing lag
   - No need to wait for tapping-term during normal typing flow

3. **Balanced flavor**: Activates modifier when another key is pressed and released while holding
   - Makes timing largely irrelevant during normal typing patterns
   - Only need to wait past tapping-term (280ms) for standalone modifiers or same-hand combos

**Configuration:**
```c
// Left-hand home row mods
hml: homerow_mods_left {
    flavor = "balanced";
    tapping-term-ms = <280>;
    quick-tap-ms = <175>;
    require-prior-idle-ms = <150>;
    hold-trigger-key-positions = <KEYS_R THUMBS>;  // Only triggers on opposite hand
    hold-trigger-on-release;
};
```

### Layer System

**4 layers with tri-layer activation:**
- **DEF** - Base QWERTY with home row mods (Shift/GUI/Alt/Ctrl)
- **NAV** - French accented characters (left) + navigation/media (right)
- **SYM** - Symbols and brackets with home row mods
- **NUM** - Function keys + numpad (auto-activates when NAV + SYM held together)

### French Character Support

Implements 13 macros for French accented characters using US International dead key sequences:
- Accented e: È, É, Ê, Ë
- Other vowels: À, Ù, Ô, Û
- Cedilla: Ç
- Standalone dead keys: `, ^, ~, ´, ¨

**Requirements:** OS keyboard layout must be set to "US International" for dead keys to work.

### Home Row Mod Pattern

Consistent across all layers:
- **Left hand:** Shift(A), GUI(S), Alt(D), Ctrl(F)
- **Right hand:** Ctrl(J), Alt(K), GUI(L), Shift(;)

### Thumb Cluster Layout

- **Left (4 keys):** Mouse Left | Shift | Enter | NAV layer
- **Right (4 keys):** SYM layer | Space | TMUX (Ctrl+B) | Mouse Right

Mouse buttons are always accessible on the base layer for trackball use.

### Additional Features

- TMUX prefix macro (Ctrl+B) for terminal workflow
- Bootloader access on SYM and NUM layers
- Middle click on NAV layer
- NumLock toggle on NAV layer
- Caps Word support

## Building the Firmware

Follow the standard ZMK build process:

```bash
# Using GitHub Actions (recommended)
# Push changes to trigger automatic build

# Or local build with west
west build -d build/left -b nice_nano_v2 -- -DSHIELD=keyball44_left
west build -d build/right -b nice_nano_v2 -- -DSHIELD=keyball44_right
```

## Files

- `config/keyball44.keymap` - Main keymap configuration
- `config/keyball44.conf` - Keyboard-level configuration
- `config/boards/shields/keyball_nano/` - Board definition files
- `build.yaml` - GitHub Actions build configuration

## Testing Checklist

After flashing firmware:

- [ ] Home row mods timing (should feel natural, no delays)
- [ ] French characters work with US International layout
- [ ] Layer switching (NAV, SYM, tri-layer NUM)
- [ ] Mouse buttons (left, right, middle click)
- [ ] TMUX prefix sends Ctrl+B
- [ ] Standalone dead keys produce correct symbols
- [ ] Positional hold-tap (mods only activate on opposite-hand keypresses)

## Migration from QMK

This configuration preserves the original Piantor Pro QMK keymap while adding ZMK-specific improvements:

1. **Preserved:**
   - 4-layer system with tri-layer
   - Home row mod positions
   - French character implementation (using macros instead of process_record_user)
   - Thumb cluster layout
   - TMUX prefix macro

2. **Enhanced:**
   - Timeless homerow mods for better typing feel
   - Positional hold-tap prevents same-hand false triggers
   - Integrated trackball support (mouse buttons on thumbs)
   - 8 extra keys utilized (44 vs 36 keys)

## Timeless Homerow Mods Explained

### The Problem with Traditional Home Row Mods

Traditional home row mods rely purely on timing: hold longer than `tapping-term-ms` = modifier, shorter = tap. This creates several issues:

1. **Typing delays**: Must wait for tapping-term to expire on every home row key
2. **Inconsistent timing**: Requires perfectly consistent typing speed
3. **False triggers**: Accidentally holding a key too long activates the modifier
4. **Same-hand rolls**: Rolling keys on one hand can trigger unwanted mods

### How Timeless Home Row Mods Solve This

**1. Positional Hold-Tap**
```c
hold-trigger-key-positions = <KEYS_R THUMBS>;  // For left-hand mods
```
- Left-hand mods only activate when you press a key on the RIGHT side
- Right-hand mods only activate when you press a key on the LEFT side
- Same-hand key rolls never trigger modifiers accidentally

**2. Require-Prior-Idle (150ms)**
```c
require-prior-idle-ms = <150>;
```
- After typing a normal key, if you press a home row key within 150ms, it's immediately a tap
- Eliminates waiting for tapping-term during normal typing flow
- Makes typing feel instant and responsive

**3. Balanced Flavor**
```c
flavor = "balanced";
```
- If you press another key while holding, it activates the modifier
- No need to wait for exact timing during typical mod+key combos
- Works naturally with your typing rhythm

**4. Hold-Trigger-On-Release**
```c
hold-trigger-on-release;
```
- Allows combining multiple modifiers on the same hand (e.g., Shift+GUI on left hand)
- Waits until the trigger key is released to decide hold vs tap
- Essential for complex modifier combinations

### When You Still Need to Wait (280ms)

Only two scenarios require waiting past the tapping-term:

1. **Same-hand mod+key combos**: e.g., using GUI(S) while holding the mouse with your right hand
2. **Standalone modifiers**: Pressing just the modifier key (e.g., Windows key alone)

Both scenarios are rare in normal typing, making the system effectively "timeless" for regular use.

## References

- [urob's ZMK config](https://github.com/urob/zmk-config) - Original timeless homerow mods implementation
- [ZMK Documentation](https://zmk.dev/docs) - Official ZMK firmware docs
- [Design Document](../../docs/plans/2025-11-24-keyball44-zmk-migration-design.md) - Detailed migration design
