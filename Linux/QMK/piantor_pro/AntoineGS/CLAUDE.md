# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Structure

This is a QMK keyboard configuration for the Beekeeb Piantor Pro keyboard. The actual keymap lives in the QMK firmware repository at `/home/antoinegs/qmk_firmware/keyboards/beekeeb/piantor_pro/keymaps/AntoineGS`, which is symlinked from this configurations repository.

**Key files:**
- `keymap.c` - Main keymap definition with layout matrices and custom keycode handlers
- `keymap.h` - Custom keycode enumerations and layer definitions
- `config.h` - QMK configuration (tap timing, home row mods settings)
- `rules.mk` - Feature flags for compilation

## Build Commands

**Compile the firmware:**
```bash
qmk compile -kb beekeeb/piantor_pro -km AntoineGS
```

**Flash to keyboard:**
```bash
qmk flash -kb beekeeb/piantor_pro -km AntoineGS
```

The compiled UF2 file will be at `.build/beekeeb_piantor_pro_AntoineGS.uf2` in the QMK firmware directory.

## Architecture

### Layer System
Four layers using tri-layer activation:
- `DEF` - Base QWERTY with home row mods
- `NAV` - French accented characters + navigation keys
- `SYM` - Symbols and special characters
- `NUM` - Function keys + numpad (activated when both NAV and SYM are held)

### Home Row Mods Pattern
Home row keys use mod-tap (dual function): tap for character, hold for modifier.
- Left hand: Shift(A), GUI(S), Alt(D), Ctrl(F)
- Right hand: Ctrl(J), Alt(K), GUI(L), Shift(;)

### Custom Keycode System

**Critical pattern for custom keycodes:**

When a custom keycode (from `keymap.h` enum) is used in a mod-tap function like `GUI_T()`, `ALT_T()`, or `CTL_T()`, it **requires a handler** in `process_record_user()`.

**Example:**
```c
// In keymap - using C_EGRV in a mod-tap
GUI_T(C_EGRV)

// Required handler in process_record_user()
case GUI_T(C_EGRV):
  return process_advanced_mt_keycode(C_EGRV, record);
  break;
```

**Two handler patterns exist:**

1. `process_advanced_mt_keycode()` - For custom keycodes that need their own `process_record_user()` handling (accented letters, complex macros)
2. `tap_code16_advanced_mt_keycode()` - For simple QMK keycodes that don't need additional processing (brackets, symbols)

**Why this matters:** QMK doesn't automatically forward mod-tap custom keycodes to their base handlers. Without the mod-tap handler, the key will do nothing when tapped (though the hold modifier will still work).

### French Accented Characters

Accented letters use US International dead key sequences:
```c
// Sends: grave accent + letter
send_accented_letter(record, US_DGRV, US_E) // produces è

// Sends: circumflex + letter
send_accented_letter(record, US_DCIR, US_E) // produces ê

// Sends: acute accent + letter
send_accented_letter(record, US_ACUT, US_E) // produces é
```

The function temporarily removes shift to type the dead key, then restores mods for the letter.

## Common Issues

**Custom keycode doesn't work after moving to mod-tap position:**
- Check if a handler exists in `process_record_user()` for the mod-tap version
- Pattern: moving keys between plain positions and home row mod positions requires adding/removing handlers

**Accented character types wrong character:**
- Verify the dead key and letter combination in `send_accented_letter()` calls
- Check that `keymap_us_international.h` is included
