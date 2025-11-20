#define LA_SYM MO(SYM)
#define LA_NAV MO(NAV)
#define LA_NUM MO(NUM)

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
  C_TMUX, // tmux prefix
};

enum layers {
  DEF,
  SYM,
  NAV,
  NUM,
};
