**FREE
// Interactive behavioral test for ERRMSG (see tests/run_interactive.sh).
//
// Pass 1: *IN61 is on, but ORDER is not on the display yet, so its ERRMSG is
// not in effect: the screen comes up normally, the cursor on NOTE, the first
// field, and *IN61 stays on. The operator keys N1, Tab, ABC, Enter.
//
// Pass 2: ORDER is on the display and *IN61 is still on, so the message is
// shown and the screen is kept: the program's new NOTE and QTY are not
// sent. The cursor goes to QTY, the field in error, so the operator's 12
// lands there with no Tab. The input turns the response indicator 61 off.

DCL-F TEST32_ERRMSG WORKSTN;

*IN61 = *ON;
EXFMT ORDER;
IF *IN61;
  DSPLY 'RESULT:P1IN61=1';
ENDIF;
DSPLY ('RESULT:P1QTY=' + %TRIM(QTY));

NOTE = 'CHANGED';
QTY = 'ZZZZZ';
EXFMT ORDER;
DSPLY ('RESULT:QTY=' + %TRIM(QTY));
DSPLY ('RESULT:NOTE=' + %TRIM(NOTE));
IF NOT *IN61;
  DSPLY 'RESULT:IN61=0';
ENDIF;

*INLR = *ON;
