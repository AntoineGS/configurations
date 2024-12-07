// Copyright 2023 QMK
// SPDX-License-Identifier: GPL-2.0-or-later

#include QMK_KEYBOARD_H
#include "keymap_us_international.h"
// https://github.com/qmk/qmk_firmware/blob/master/quantum/keymap_extras/keymap_us_international.h
//#define QUICK_TAP_TERM 0 // used to allow repeating of character with mod taps, 0 disables it

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
                SEND_STRING("^ ");
            }
            break;
        case C_QUOT:
            if (record->event.pressed) {
                if (get_mods() & MOD_MASK_SHIFT) {
                    SEND_STRING("\" ");
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
    }
    return true;
};

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    [0] = LAYOUT_split_3x6_3(
        // Base for writing text
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        KC_TAB,        US_Q,         US_W,         US_E,         US_R,         US_T,                     US_Y,         US_U,        US_I,         US_O,         US_P,       KC_BSPC,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        KC_ESC,        US_A,     ALT_T(US_S),   GUI_T(US_D),  CTL_T(US_F),     US_G,                     US_H,     CTL_T(US_J),  GUI_T(US_K),  ALT_T(US_L),    US_SCLN,      C_QUOT,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,       US_Z,         KC_X,         US_C,         US_V,         US_B,                     US_N,         US_M,       US_COMM,      US_DOT,       US_SLSH,      KC_DEL,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                   SFT_T(OSM(MOD_LSFT)),   KC_ENT,     MO(1),  MO(2),         KC_SPC,       XXXXXXX
                                                     //`------------------------------------'  `--------------------------------------'

  ),
    [1] = LAYOUT_split_3x6_3(
        // Symbols
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        XXXXXXX,      US_EXLM,       US_AT,       US_HASH,      US_DLR,       US_PERC,                 C_CIRC,       US_AMPR,      US_ASTR,      XXXXXXX,      XXXXXXX,      KC_BSPC,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        KC_ESC,       US_LCBR,      US_LABK,      US_LBRC,      US_LPRN,      US_EQL,                  US_UNDS,      US_RPRN,      US_RBRC,      US_RABK,      US_RCBR,      US_COLN,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,      XXXXXXX,       C_DTIL,       C_DGRV,      US_SLSH,      US_PLUS,                 US_MINS,      US_BSLS,      XXXXXXX,      US_NDAC,      US_PIPE,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                   SFT_T(OSM(MOD_LSFT)),   KC_ENT,   _______,  MO(3),         KC_SPC,       XXXXXXX
                                                     //`------------------------------------'  `--------------------------------------'

  ),
    [2] = LAYOUT_split_3x6_3(
        // Numbers, French and Navigation
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        XXXXXXX,       US_1,         US_2,         US_3,         US_4,         US_5,                     US_6,         US_7,        US_8,         US_9,         US_0,        KC_BSPC,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        KC_ESC,       XXXXXXX,  ALT_T(XXXXXXX),GUI_T(XXXXXXX),CTL_T(XXXXXXX), XXXXXXX,                 KC_LEFT,      KC_DOWN,       KC_UP,       KC_RIGHT,     XXXXXXX,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,      US_DIAE,      US_DCIR,      US_DGRV,      US_ACUT,      US_CCED,                 KC_HOME,      KC_PGDN,       KC_PGUP,      KC_END,      XXXXXXX,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                   SFT_T(OSM(MOD_LSFT)),    KC_ENT,    MO(3),  _______,       KC_SPC,       XXXXXXX
                                                     //`------------------------------------'  `--------------------------------------'

  ),

    [3] = LAYOUT_split_3x6_3(
        // Function Keys
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        KC_F1,         KC_F2,        KC_F3,        KC_F4,        KC_F5,        KC_F6,                   KC_F7,        KC_F8,         KC_F9,       KC_F10,      KC_F11,       KC_F12,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        KC_ESC,   ALT_T(XXXXXXX),GUI_T(XXXXXXX),  XXXXXXX,  CTL_T(XXXXXXX),   XXXXXXX,                 XXXXXXX,  CTL_T(XXXXXXX),   XXXXXXX,  GUI_T(XXXXXXX),ALT_T(XXXXXXX),  XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,                 XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                   SFT_T(OSM(MOD_LSFT)),    KC_ENT,      _______,  _______,        KC_SPC,       MO(4)
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
                                                         XXXXXXX,       KC_ENT,      _______,  _______,        KC_SPC,      _______
                                                     //`------------------------------------'  `--------------------------------------'
  )
};
