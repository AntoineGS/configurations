// Copyright 2023 QMK
// SPDX-License-Identifier: GPL-2.0-or-later

#include QMK_KEYBOARD_H
#include "keymap_us_international.h"
// https://github.com/qmk/qmk_firmware/blob/master/quantum/keymap_extras/keymap_us_international.h

enum custom_keycodes {
    C_CIRC = SAFE_RANGE,
    C_QUOT,
    C_DGRV,
    C_DTIL
};

bool process_record_user(uint16_t keycode, keyrecord_t *record) {
    switch (keycode) {
        // might need some work with modifiers like SHIFT for C_QUOT to get double quotes
        case C_CIRC:
            if (record->event.pressed) {
                SEND_STRING("ˆ"); // might have to be SEND_STRING(SS_TAP(US_DCIR) SS_TAP(KC_SPC))
            }
            break;
        case C_QUOT:
            if (record->event.pressed) {
                SEND_STRING("´"); // might have to be SEND_STRING(SS_TAP(US_ACUT) SS_TAP(KC_SPC))
            }
            break;
        case C_DGRV:
                if (record->event.pressed) {
                    SEND_STRING("`"); // might have to be SEND_STRING(SS_TAP(US_DGRV) SS_TAP(KC_SPC))
                }
            break;
        case C_DTIL:
            if (record->event.pressed) {
                SEND_STRING("~"); // might have to be SEND_STRING(SS_TAP(US_TILD) SS_TAP(KC_SPC))
            }
            break;
    }
    return true;
};

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    [0] = LAYOUT_split_3x6_3(
        // Base for writing text
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        KC_TAB,        US_Q,         US_W,         US_E,         US_R,         US_T,                     US_Y,         US_U,        US_I,         US_O,         US_P,       KC_BSPC,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        KC_ESC,     LAlt(US_A),  LGui_T(US_S), LSft_T(US_D),  LCtl_T(US_F),    US_G,                     US_H,    LCtl_T(US_J), LSft_T(US_K), LGui_T(US_L),LAlt_T(US_SCLN), C_QUOT,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,       US_Z,         KC_X,         US_C,         US_V,         US_B,                     US_N,         US_M,       US_COMM,      US_DOT,       US_SLSH,     XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                         XXXXXXX,       MO(1),        KC_SPC,    KC_ENT,       MO(2),       XXXXXXX
                                                     //`------------------------------------'  `--------------------------------------'

  ),
    [1] = LAYOUT_split_3x6_3(
        // Symbols
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        XXXXXXX,      US_EXLM,       US_AT,       US_HASH,      US_DLR,       US_PERC,                 C_CIRC,       US_AMPR,      US_ASTR,      XXXXXXX,      XXXXXXX,      KC_BSPC,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        KC_ESC,  LAlt(US_LCBR),LGui_T(US_LABK),LSft_T(US_LBRC),LCtl_T(US_LPRN), US_PLUS,              US_MINS, LCtl_T(US_RPRN),LSft_T(US_RBRC),LGui_T(US_RABK),LAlt_T(US_RCBR),US_COLN,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,      XXXXXXX,       C_DGRV,       C_TILD,      US_SLSH,      US_EQL,                  US_UNDS,      US_BSLS,       XXXXXXX,      XXXXXXX,     US_PIPE,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                         XXXXXXX,       MO(3),       KC_SPC,   KC_ENT,        _______,       XXXXXXX
                                                     //`------------------------------------'  `--------------------------------------'

  ),
    [2] = LAYOUT_split_3x6_3(
        // Numbers, French and Navigation
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        XXXXXXX,       US_1,         US_2,         US_3,         US_4,         US_5,                     US_6,         US_7,        US_8,         US_9,         US_0,        KC_BSPC,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        KC_ESC, LAlt(US_DIAE),LGui_T(US_DCIR),LSft_T(US_DGRV),LCtl_T(US_ACUT),  US_CCED,               KC_LEFT,      KC_DOWN,       KC_UP,       KC_RIGHT,     XXXXXXX,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,                 KC_HOME,      KC_PGDN,       KC_PGUP,      KC_END,      XXXXXXX,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                         XXXXXXX,      _______,       KC_SPC,   KC_ENT,        MO(3),       XXXXXXX
                                                     //`------------------------------------'  `--------------------------------------'

  ),

    [3] = LAYOUT_split_3x6_3(
        // Function Keys
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        KC_F1,         KC_F2,        KC_F3,        KC_F4,        KC_F5,        KC_F6,                   KC_F7,        KC_F8,         KC_F9,       KC_F10,      KC_F11,       KC_F12,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        KC_ESC,       LAlt(),      LGui_T(),      LSft_T(),    LCtl_T(),      XXXXXXX,                 XXXXXXX,     LCtl_T(),      LSft_T(),    LGui_T(),     LAlt_T(),      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,                 XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                         XXXXXXX,       _______,      KC_SPC,   KC_ENT,        _______,       MO(4)
                                                     //`------------------------------------'  `--------------------------------------'
  ),

    [4] = LAYOUT_split_3x6_3(
        // Bootloader
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        QK_BOOT,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,                 XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,                 XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,                 XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                         XXXXXXX,       _______,      KC_SPC,   KC_ENT,        _______,       _______
                                                     //`------------------------------------'  `--------------------------------------'
  )
};
