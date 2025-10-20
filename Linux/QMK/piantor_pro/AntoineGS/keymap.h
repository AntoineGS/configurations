#define LA_SYM MO(SYM)
#define LA_NAV MO(NAV)
#define LA_NUM MO(NUM)
#define MAX_DEFERRED_EXECUTORS 10
#define CHORDAL_HOLD
#undef TAPPING_TERM
#define TAPPING_TERM 1000
#define FLOW_TAP_TERM 150
// #define RETRO_TAPPING
// #define QUICK_TAP_TERM 0 // used to allow repeating of character with mod
// taps, 0 disables it

enum custom_keycodes {
  C_CIRC = SAFE_RANGE,
  C_QUOT, // '
  C_DGRV, // `
  C_DTIL, // ~
  C_AGRV, // À
  C_UGRV, // Ù
  C_UCIR, // Û
  C_OCIR, // Ô
  SW_WIN, // Switch to next window         (cmd-tab)
  C_SCLN,
  C_EAIG, // É
  C_ECIR, // Ê
  C_EGRV, // È
  C_ETRE, // Ë
  C_DIAE, // ¨
  C_DCIR, // ^
  C_LCBR, // {
  C_LBRC, // [
  C_LPRN, // (
  C_RPRN, // )
  C_RBRC, // ]
  C_RCBR, // }
  C_TNUM, // numlock only while pressed
};

enum layers {
  DEF,
  SYM,
  NAV,
  NUM,
};
