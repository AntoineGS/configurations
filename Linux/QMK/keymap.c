// Copyright 2023 QMK
// SPDX-License-Identifier: GPL-2.0-or-later

#include QMK_KEYBOARD_H
#include "keymap_us_international.h"
#include "oneshot.h"
#include "swapper.h"
// https://github.com/qmk/qmk_firmware/blob/master/quantum/keymap_extras/keymap_us_international.h
//#define QUICK_TAP_TERM 0 // used to allow repeating of character with mod taps, 0 disables it

#define HOME G(KC_LEFT)
#define END G(KC_RGHT)
#define FWD G(KC_RBRC)
#define BACK G(KC_LBRC)
#define TAB_L G(S(KC_LBRC))
#define TAB_R G(S(KC_RBRC))
#define SPACE_L A(G(KC_LEFT))
#define SPACE_R A(G(KC_RGHT))
#define LA_SYM MO(SYM)
#define LA_NAV MO(NAV)

enum custom_keycodes {
    C_CIRC = SAFE_RANGE,
    C_QUOT, // '
    C_DGRV, // `
    C_DTIL, // ~
    C_EAIG, // É
    C_ECIR, // Ê
    C_EGRV, // È
    C_ETRE, // Ë
    C_AGRV, // À
    C_UGRV, // Ù
    OS_SHFT,
    OS_CTRL,
    OS_ALT,
    OS_CMD,
    SW_WIN,  // Switch to next window         (cmd-tab)
    SW_LANG
};

enum layers {
    DEF,
    SYM,
    NAV,
    NUM,
};

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    [DEF] = LAYOUT_split_3x6_3(
        // Base for writing text
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        KC_TAB,        US_Q,         US_W,         US_E,         US_R,         US_T,                     US_Y,         US_U,        US_I,         US_O,         US_P,       KC_BSPC,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        KC_ESC,        US_A,         US_S,         US_D,         US_F,         US_G,                     US_H,         US_J,        US_K,         US_L,        US_SCLN,      C_QUOT,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,       US_Z,         KC_X,         US_C,         US_V,         US_B,                     US_N,         US_M,       US_COMM,      US_DOT,       US_SLSH,      KC_DEL,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                          KC_LSFT,      KC_ENT,       LA_NAV,  LA_SYM,         KC_SPC,       KC_LCTL
                                                     //`------------------------------------'  `--------------------------------------'

  ),
    [SYM] = LAYOUT_split_3x6_3(
        // Symbols
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        XXXXXXX,      US_EXLM,       US_AT,       US_HASH,      US_DLR,       US_PERC,                 C_CIRC,       US_AMPR,      US_ASTR,      XXXXXXX,      XXXXXXX,      KC_BSPC,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,      C_DGRV,       US_PIPE,      C_DTIL,       US_COLN,      US_EQL,                  US_UNDS,      OS_ALT,       OS_CMD,       OS_CTRL,      OS_SHFT,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,      US_LCBR,      US_LBRC,      US_SLSH,      US_LPRN,      US_PLUS,                 US_MINS,      US_RPRN,      US_BSLS,      US_RBRC,      US_RCBR,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                          KC_LSFT,      KC_ENT,      _______,  _______,       XXXXXXX,      XXXXXXX
                                                     //`------------------------------------'  `--------------------------------------'

  ),
    [NAV] = LAYOUT_split_3x6_3(
        // French and Navigation, add more french here
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        XXXXXXX,      US_DIAE,      US_DCIR,      US_DGRV,      US_ACUT,      C_UGRV,                  KC_WHOM,      KC_PSCR,      XXXXXXX,      XXXXXXX,      KC_VOLU,      KC_BSPC,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,      OS_SHFT,      OS_CTRL,      OS_CMD,       OS_ALT,       C_AGRV,                  KC_LEFT,      KC_DOWN,       KC_UP,       KC_RIGHT,     KC_VOLD,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,      C_ETRE,       C_ECIR,       C_EGRV,       C_EAIG,       US_CCED,                 KC_HOME,      KC_PGDN,       KC_PGUP,      KC_END,      KC_MUTE,      KC_CALC,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                         XXXXXXX,      XXXXXXX,      _______,  _______,       KC_SPC,       XXXXXXX
                                                     //`------------------------------------'  `--------------------------------------'

  ),

    [NUM] = LAYOUT_split_3x6_3(
        // Function Keys
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        XXXXXXX,       US_1,         US_2,         US_3,         US_4,         US_5,                     US_6,        US_7,         US_8,        US_9,         US_0,         KC_BSPC,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,       OS_SHFT,      OS_CTRL,      OS_CMD,       OS_ALT,      XXXXXXX,                 XXXXXXX,       OS_ALT,       OS_CMD,      OS_CTRL,      OS_SHFT,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        KC_F1,         KC_F2,        KC_F3,        KC_F4,        KC_F5,        KC_F6,                   KC_F7,        KC_F8,        KC_F9,       KC_F10,       KC_F11,       KC_F12,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                         XXXXXXX,      XXXXXXX,      _______,  _______,        KC_SPC,       QK_BOOT
                                                     //`------------------------------------'  `--------------------------------------'
  )
};


bool is_oneshot_cancel_key(uint16_t keycode) {
    switch (keycode) {
    case LA_SYM:
    case LA_NAV:
        return true;
    default:
        return false;
    }
}

bool is_oneshot_ignored_key(uint16_t keycode) {
    switch (keycode) {
    case LA_SYM:
    case LA_NAV:
    case KC_LSFT:
    case OS_SHFT:
    case OS_CTRL:
    case OS_ALT:
    case OS_CMD:
        return true;
    default:
        return false;
    }
}

bool sw_win_active = false;
bool sw_lang_active = false;

oneshot_state os_shft_state = os_up_unqueued;
oneshot_state os_ctrl_state = os_up_unqueued;
oneshot_state os_alt_state = os_up_unqueued;
oneshot_state os_cmd_state = os_up_unqueued;

bool process_record_user(uint16_t keycode, keyrecord_t *record) {
    update_swapper(
        &sw_win_active, KC_LGUI, KC_TAB, SW_WIN,
        keycode, record
    );
    update_swapper(
        &sw_lang_active, KC_LCTL, KC_SPC, SW_LANG,
        keycode, record
    );

    update_oneshot(
        &os_shft_state, KC_LSFT, OS_SHFT,
        keycode, record
    );
    update_oneshot(
        &os_ctrl_state, KC_LCTL, OS_CTRL,
        keycode, record
    );
    update_oneshot(
        &os_alt_state, KC_LALT, OS_ALT,
        keycode, record
    );
    update_oneshot(
        &os_cmd_state, KC_LCMD, OS_CMD,
        keycode, record
    );

    switch (keycode) {
        // might need some work with modifiers like SHIFT for C_QUOT to get double quotes
        case C_CIRC:
            if (record->event.pressed) {
                SEND_STRING("^ ");
            }
            break;
        case C_QUOT:
            if (record->event.pressed) {
                if (get_mods() & MOD_MASK_SHIFT) {
                    SEND_STRING("\" ");
                    register_code(KC_LSFT);
                    return false;
                } else {
                    SEND_STRING("' "); // might have to be SEND_STRING(SS_TAP(US_ACUT) SS_TAP(KC_SPC))
                }
            }
            break;
        case C_DGRV:
                if (record->event.pressed) {
                    SEND_STRING("` "); // might have to be SEND_STRING(SS_TAP(US_DGRV) SS_TAP(KC_SPC))
                }
            break;
        case C_DTIL:
            if (record->event.pressed) {
                SEND_STRING("~ "); // might have to be SEND_STRING(SS_TAP(US_TILD) SS_TAP(KC_SPC))
            }
            break;
        case C_EAIG:
            if (record->event.pressed) {
                if (get_mods() & MOD_MASK_SHIFT) {
                    unregister_code(KC_LSFT);
                    SEND_STRING("'E");
                    register_code(KC_LSFT);
                    return false;
                } else {
                    SEND_STRING("'e");
                }
            }
            break;
        case C_ECIR:
            if (record->event.pressed) {
                if (get_mods() & MOD_MASK_SHIFT) {
                    unregister_code(KC_LSFT);
                    SEND_STRING("^E");
                    register_code(KC_LSFT);
                    return false;
                } else {
                    SEND_STRING("^e");
                }
            }
            break;
        case C_EGRV:
            if (record->event.pressed) {
                if (get_mods() & MOD_MASK_SHIFT) {
                    unregister_code(KC_LSFT);
                    SEND_STRING("`E");
                    register_code(KC_LSFT);
                    return false;
                } else {
                    SEND_STRING("`e");
                }
            }
            break;
        case C_ETRE:
            if (record->event.pressed) {
                if (get_mods() & MOD_MASK_SHIFT) {
                    unregister_code(KC_LSFT);
                    SEND_STRING("\"E");
                    register_code(KC_LSFT);
                    return false;
                } else {
                    SEND_STRING("\"e");
                }
            }
            break;
        case C_AGRV:
            if (record->event.pressed) {
                if (get_mods() & MOD_MASK_SHIFT) {
                    unregister_code(KC_LSFT);
                    SEND_STRING("`A");
                    register_code(KC_LSFT);
                    return false;
                } else {
                    SEND_STRING("`a");
                }
            }
            break;
        case C_UGRV:
            if (record->event.pressed) {
                if (get_mods() & MOD_MASK_SHIFT) {
                    unregister_code(KC_LSFT);
                    SEND_STRING("`U");
                    register_code(KC_LSFT);
                    return false;
                } else {
                    SEND_STRING("`u");
                }
            }
            break;
    }

    return true;
}

layer_state_t layer_state_set_user(layer_state_t state) {
    return update_tri_layer_state(state, SYM, NAV, NUM);
}
