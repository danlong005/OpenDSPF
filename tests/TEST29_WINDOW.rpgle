**FREE
// ─────────────────────────────────────────────────────────────────────
//  TEST29 — a WINDOW record. Its field and literal positions count from
//  the window's inside, as on IBM i: the literal at line 1 position 1
//  of WINDOW(9 21 7 40) is at screen line 10, position 23, and the field
//  at line 3 position 10 is at screen line 12, position 32. The harness
//  checks those screen positions in the raw capture; this program checks
//  the field's input comes back.
// ─────────────────────────────────────────────────────────────────────

DCL-F TEST29_WINDOW WORKSTN;

ANSWER = ' ';
EXFMT ASK;
DSPLY ('RESULT:ANSWER=' + ANSWER);
*INLR = *ON;
