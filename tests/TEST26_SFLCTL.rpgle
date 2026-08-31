**FREE
// Interactive driver for TEST26_SFLCTL — see tests/run_interactive.sh.
// The real-world subfile load-then-display idiom, which writes the control
// record twice:
//
//   *IN90 on  -> WRITE ROWCTL   clears the subfile
//   *IN90 off -> load rows      three of them
//              -> WRITE ROWCTL   must NOT clear; this is the regression
//   *IN91 on  -> EXFMT ROWCTL   display control record and rows
//
// If that second WRITE still wiped the subfile the screen would come back
// with no rows and no Bottom marker, which is what the golden checks.

DCL-F TEST26_SFLCTL WORKSTN;

*IN90 = *ON;
WRITE ROWCTL;
*IN90 = *OFF;

ITEM = 'ITEM0001'; WRITE ROWSFL;
ITEM = 'ITEM0002'; WRITE ROWSFL;
ITEM = 'ITEM0003'; WRITE ROWSFL;

WRITE ROWCTL;

*IN91 = *ON;
EXFMT ROWCTL;

DSPLY 'RESULT:DONE=1';

*INLR = *ON;
