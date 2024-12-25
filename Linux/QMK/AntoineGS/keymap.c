// Copyright 2023 QMK
// SPDX-License-Identifier: GPL-2.0-or-later

#include QMK_KEYBOARD_H
#include "keymap_us_international.h"
#include "keymap.h"
// https://github.com/qmk/qmk_firmware/blob/master/quantum/keymap_extras/keymap_us_international.h
//#define QUICK_TAP_TERM 0 // used to allow repeating of character with mod taps, 0 disables it

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    [DEF] = LAYOUT_split_3x6_3(
        // Base for writing text
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        KC_ESC,        US_Q,         US_W,         US_E,         US_R,         US_T,                     US_Y,         US_U,        US_I,         US_O,         US_P,       KC_BSPC,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        KC_TAB,        C_A,          C_S,          C_D,          C_F,          US_G,                     US_H,         C_J,         C_K,          C_L,         C_SCLN,       C_QUOT,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,       US_Z,         KC_X,         US_C,         US_V,         US_B,                     US_N,         US_M,       US_COMM,      US_DOT,       US_SLSH,      KC_DEL,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                         KC_LSFT,       KC_ENT,       LA_NAV,  LA_SYM,         KC_SPC,        MS_BTN1
                                                     //`------------------------------------'  `--------------------------------------'
  ),

    [NAV] = LAYOUT_split_3x6_3(
        // French and Navigation
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        XXXXXXX,      US_DIAE,      US_DCIR,      US_DGRV,      US_ACUT,      XXXXXXX,                 KC_WHOM,      KC_PSCR,      XXXXXXX,      XXXXXXX,      KC_VOLU,      _______,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        KC_TAB,       C_ETRE,       C_ECIR,       C_EGRV,       C_EAIG,       C_AGRV,                  KC_LEFT,      KC_DOWN,       KC_UP,       KC_RIGHT,     KC_VOLD,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,      XXXXXXX,      C_OCIR,       C_UGRV,       C_UCIR,       US_CCED,                 KC_HOME,      KC_PGDN,       KC_PGUP,      KC_END,      KC_MUTE,      KC_CALC,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                         XXXXXXX,      XXXXXXX,      _______,  LA_NUM,        XXXXXXX,      _______
                                                     //`------------------------------------'  `--------------------------------------'
  ),

    [SYM] = LAYOUT_split_3x6_3(
        // Symbols
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        XXXXXXX,      US_EXLM,       US_AT,       US_HASH,      US_DLR,       US_PERC,                 C_CIRC,       US_AMPR,      US_ASTR,      XXXXXXX,      XXXXXXX,      _______,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,      KC_LSFT,      C_LCBR,       C_LBRC,       C_LPRN,       KC_PPLS,                 KC_PMNS,      C_RPRN,       C_RBRC,       C_RCBR,       KC_LSFT,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        QK_BOOT,      XXXXXXX,      C_DGRV,       US_PIPE,      C_DTIL,       US_EQL,                  US_UNDS,      XXXXXXX,      XXXXXXX,      XXXXXXX,      US_BSLS,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                          XXXXXXX,     XXXXXXX,       LA_NUM,  _______,       XXXXXXX,       _______
                                                     //`------------------------------------'  `--------------------------------------'
  ),

    [NUM] = LAYOUT_split_3x6_3(
        // Function Keys
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,                 XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      _______,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,       C_1,          C_2,          C_3,          C_4,          US_5,                     US_6,        C_7,          C_8,          C_9,          C_0,         XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        KC_F12,        KC_F1,        KC_F2,        KC_F3,        KC_F4,        KC_F5,                    KC_F6,       KC_F7,        KC_F8,        KC_F9,        KC_F10,       KC_F11,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                         QK_BOOT,      XXXXXXX,      _______,  _______,       XXXXXXX,      _______
                                                     //`------------------------------------'  `--------------------------------------'
  )
};

bool process_record_user(uint16_t keycode, keyrecord_t *record) {
    if (!process_smtd(keycode, record)) {
        return false;
    }

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
        case C_OCIR:
            if (record->event.pressed) {
                if (get_mods() & MOD_MASK_SHIFT) {
                    unregister_code(KC_LSFT);
                    SEND_STRING("^O");
                    register_code(KC_LSFT);
                    return false;
                } else {
                    SEND_STRING("^o");
                }
            }
            break;
        case C_UCIR:
            if (record->event.pressed) {
                if (get_mods() & MOD_MASK_SHIFT) {
                    unregister_code(KC_LSFT);
                    SEND_STRING("^U");
                    register_code(KC_LSFT);
                    return false;
                } else {
                    SEND_STRING("^u");
                }
            }
            break;
    }

    return true;
}

//layer_state_t layer_state_set_user(layer_state_t state) {
//    return update_tri_layer_state(state, SYM, NAV, NUM);
//}

void on_smtd_action(uint16_t keycode, smtd_action action, uint8_t tap_count) {
    if (action == SMTD_ACTION_TAP) {
        switch (keycode) {
            case C_ETRE:
                if (get_mods() & MOD_MASK_SHIFT) {
                    unregister_code(KC_LSFT);
                    SEND_STRING("\"E");
                    register_code(KC_LSFT);
                } else {
                    SEND_STRING("\"e");
                }
                return;
            case C_EAIG:
                if (get_mods() & MOD_MASK_SHIFT) {
                    unregister_code(KC_LSFT);
                    SEND_STRING("'E");
                    register_code(KC_LSFT);
                } else {
                    SEND_STRING("'e");
                }
                return;
            case C_ECIR:
                if (get_mods() & MOD_MASK_SHIFT) {
                    unregister_code(KC_LSFT);
                    SEND_STRING("^E");
                    register_code(KC_LSFT);
                } else {
                    SEND_STRING("^e");
                }
                return;

            case C_EGRV:
                if (get_mods() & MOD_MASK_SHIFT) {
                    unregister_code(KC_LSFT);
                    SEND_STRING("`E");
                    register_code(KC_LSFT);
                } else {
                    SEND_STRING("`e");
                }
                return;

        }
    }

    switch (keycode) {
        SMTD_MT(C_A, US_A, KC_LSFT)
        SMTD_MT(C_S, US_S, KC_LEFT_GUI)
        SMTD_MT(C_D, US_D, KC_LEFT_ALT)
        SMTD_MT(C_F, US_F, KC_LEFT_CTRL)
        SMTD_MT(C_SCLN, US_SCLN, KC_LSFT)
        SMTD_MT(C_L, US_L, KC_LEFT_GUI)
        SMTD_MT(C_K, US_K, KC_LEFT_ALT)
        SMTD_MT(C_J, US_J, KC_LEFT_CTRL)
        SMTD_MT(C_ETRE, C_ETRE, KC_LSFT)
        SMTD_MT(C_ECIR, C_ECIR, KC_LEFT_GUI)
        SMTD_MT(C_EGRV, C_EGRV, KC_LEFT_ALT)
        SMTD_MT(C_EAIG, C_EAIG, KC_LEFT_CTRL)
        SMTD_MT(C_LCBR, US_LCBR, KC_LEFT_GUI)
        SMTD_MT(C_LBRC, US_LBRC, KC_LEFT_ALT)
        SMTD_MT(C_LPRN, US_LPRN, KC_LEFT_CTRL)
        SMTD_MT(C_RPRN, US_RPRN, KC_LEFT_CTRL)
        SMTD_MT(C_RBRC, US_RBRC, KC_LEFT_ALT)
        SMTD_MT(C_RCBR, US_RCBR, KC_LEFT_GUI)
        SMTD_MT(C_1, US_1, KC_LSFT)
        SMTD_MT(C_2, US_2, KC_LEFT_GUI)
        SMTD_MT(C_3, US_3, KC_LEFT_ALT)
        SMTD_MT(C_4, US_4, KC_LEFT_CTRL)
        SMTD_MT(C_7, US_7, KC_LEFT_CTRL)
        SMTD_MT(C_8, US_8, KC_LEFT_ALT)
        SMTD_MT(C_9, US_9, KC_LEFT_GUI)
        SMTD_MT(C_0, US_0, KC_LSFT)
    }
}
