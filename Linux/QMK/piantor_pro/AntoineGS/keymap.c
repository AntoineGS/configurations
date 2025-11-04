#include QMK_KEYBOARD_H
#include "keymap.h"
#include "keymap_us_international.h"
// https://github.com/qmk/qmk_firmware/blob/master/quantum/keymap_extras/keymap_us_international.h

// clang-format off
const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    [DEF] = LAYOUT_split_3x6_3(
        // Base for writing text
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        KC_ESC,        US_Q,         US_W,         US_E,         US_R,         US_T,                     US_Y,         US_U,        US_I,         US_O,         US_P,       KC_BSPC,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        KC_TAB,     SFT_T(KC_A),  GUI_T(KC_S),  ALT_T(KC_D),  CTL_T(KC_F),     US_G,                     US_H,     CTL_T(KC_J),  ALT_T(KC_K),  GUI_T(KC_L),SFT_T(KC_SCLN),   C_QUOT,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        MS_BTN1,       US_Z,         KC_X,         US_C,         US_V,         US_B,                     US_N,         US_M,       US_COMM,      US_DOT,       US_SLSH,      KC_DEL,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                         KC_LSFT,       KC_ENT,       LA_NAV,  LA_SYM,         KC_SPC,        C_TMUX
                                                     //`------------------------------------'  `--------------------------------------'
  ),

    [NAV] = LAYOUT_split_3x6_3(
        // French and Navigation
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        _______,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,      XXXXXXX,                 KC_WHOM,      KC_PSCR,      XXXXXXX,      XXXXXXX,      KC_VOLU,      _______,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,  SFT_T(US_DIAE),GUI_T(C_DCIR),ALT_T(US_DGRV),CTL_T(US_ACUT), C_AGRV,                 KC_LEFT,      KC_DOWN,       KC_UP,       KC_RIGHT,     KC_VOLD,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        MS_BTN2,      C_TNUM,       C_ECIR,       C_EGRV,       C_EAIG,       US_CCED,                 KC_HOME,      KC_PGDN,       KC_PGUP,      KC_END,      KC_MUTE,      KC_CALC,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                         _______,      _______,      _______,  _______,        _______,      _______
                                                     //`------------------------------------'  `--------------------------------------'
  ),

    [SYM] = LAYOUT_split_3x6_3(
        // Symbols
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        _______,      US_EXLM,       US_AT,       US_HASH,      US_DLR,       US_PERC,                 C_CIRC,       US_AMPR,      US_ASTR,      XXXXXXX,      XXXXXXX,      _______,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,  SFT_T(XXXXXXX),GUI_T(KC_LCBR),ALT_T(KC_LBRC),CTL_T(KC_LPRN),KC_PPLS,                 KC_PMNS,  CTL_T(KC_RPRN),ALT_T(KC_RBRC),GUI_T(KC_RCBR),SFT_T(XXXXXXX),XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        QK_BOOT,      XXXXXXX,      C_DGRV,       US_PIPE,      C_DTIL,       US_EQL,                  US_UNDS,      XXXXXXX,      XXXXXXX,      XXXXXXX,      US_BSLS,      XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                          _______,     _______,      _______,  _______,       _______,       _______
                                                     //`------------------------------------'  `--------------------------------------'
  ),

    [NUM] = LAYOUT_split_3x6_3(
        // Function Keys
  //,-----------------------------------------------------------------------------------.          ,-----------------------------------------------------------------------------------.
        _______,       KC_F9,       KC_F10,       KC_F11,       KC_F12,       XXXXXXX,                 XXXXXXX,       US_7,         US_8,         US_9,       XXXXXXX,       _______,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,   SFT_T(KC_F5), GUI_T(KC_F6),  ALT_T(KC_F7), CTL_T(KC_F8),   XXXXXXX,                 KC_PMNS,    CTL_T(KC_4), ALT_T(KC_5),  GUI_T(KC_6),   SFT_T(KC_0),    XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------|          |-------------+-------------+-------------+-------------+-------------+-------------|
        XXXXXXX,       KC_F1,       KC_F2,        KC_F3,        KC_F4,        XXXXXXX,                 XXXXXXX,       US_1,         US_2,         US_3,       XXXXXXX,       XXXXXXX,
  //|-------------+-------------+-------------+-------------+-------------+-------------+---|  |---+-------------+-------------+-------------+-------------+-------------+-------------|
                                                         QK_BOOT,      _______,      _______,  _______,       _______,      _______
                                                     //`------------------------------------'  `--------------------------------------'
  )
};

// clang-format on

bool send_accented_letter(keyrecord_t *record, uint16_t accent_keycode,
                          uint16_t letter_keycode) {
  if (!record->event.pressed) {
    return true;
  }

  const uint8_t saved_mods = get_mods();
  unregister_mods(MOD_MASK_SHIFT);
  tap_code16(accent_keycode);
  register_mods(saved_mods);
  tap_code16(letter_keycode);
  return false;
}

// unline send_accented_letter, this will apply shift to the symbol_keycode
bool send_symbol(keyrecord_t *record, uint16_t symbol_keycode) {
  if (!record->event.pressed) {
    return true;
  }

  tap_code16(symbol_keycode);
  tap_code16(KC_SPC);
  return false;
}

bool process_advanced_mt_keycode(uint16_t keycode, keyrecord_t *record) {
  if (record->tap.count && record->event.pressed) {
    process_record_user(keycode, record);
    return false;
  }

  return true;
}

bool tap_code16_advanced_mt_keycode(uint16_t keycode, keyrecord_t *record) {
  if (record->tap.count && record->event.pressed) {
    tap_code16(keycode);
    return false;
  }

  return true;
}

bool process_record_user(uint16_t keycode, keyrecord_t *record) {
  switch (keycode) {
  case SFT_T(US_DIAE):
    return tap_code16_advanced_mt_keycode(US_DIAE, record);
    break;
  case GUI_T(C_DCIR):
    return tap_code16_advanced_mt_keycode(US_DCIR, record);
    break;
  case GUI_T(KC_LCBR):
    return tap_code16_advanced_mt_keycode(KC_LCBR, record);
    break;
  case ALT_T(KC_LBRC):
    return tap_code16_advanced_mt_keycode(KC_LBRC, record);
    break;
  case CTL_T(KC_LPRN):
    return tap_code16_advanced_mt_keycode(KC_LPRN, record);
    break;
  case CTL_T(KC_RPRN):
    return tap_code16_advanced_mt_keycode(KC_RPRN, record);
    break;
  case ALT_T(KC_RBRC):
    return tap_code16_advanced_mt_keycode(KC_RBRC, record);
    break;
  case GUI_T(KC_RCBR):
    return tap_code16_advanced_mt_keycode(KC_RCBR, record);
    break;
  case C_CIRC:
    return send_accented_letter(record, US_DCIR, KC_SPC);
    break;
  case C_QUOT:
    return send_symbol(record, US_ACUT);
    break;
  case C_DGRV:
    return send_accented_letter(record, US_DGRV, KC_SPC);
    break;
  case C_DTIL:
    return send_accented_letter(record, US_DTIL, KC_SPC);
    break;
  case C_AGRV:
    return send_accented_letter(record, US_DGRV, US_A);
    break;
  case C_UGRV:
    return send_accented_letter(record, US_DGRV, US_U);
    break;
  case C_OCIR:
    return send_accented_letter(record, US_DCIR, US_O);
    break;
  case C_UCIR:
    return send_accented_letter(record, US_DCIR, US_U);
    break;
  case C_ETRE:
    return send_accented_letter(record, US_DIAE, US_E);
    break;
  case C_EAIG:
    return send_accented_letter(record, US_ACUT, US_E);
    break;
  case C_ECIR:
    return send_accented_letter(record, US_DCIR, US_E);
    break;
  case C_EGRV:
    return send_accented_letter(record, US_DGRV, US_E);
    break;
  case C_TNUM:
    if (record->event.pressed) {
      tap_code(KC_NUM);
    } else {
      tap_code(KC_NUM);
    }
  case C_TMUX:
    if (record->event.pressed) {
      register_code(KC_LCTL);
      tap_code(KC_B);
      unregister_code(KC_LCTL);
    }
  }

  return true;
}

layer_state_t layer_state_set_user(layer_state_t state) {
  return update_tri_layer_state(state, SYM, NAV, NUM);
}
