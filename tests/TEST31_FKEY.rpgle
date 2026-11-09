**FREE
// Interactive behavioral test for %FKEY, an OpenRPG extension: the number
// of the function key that ended the last EXFMT: 3 for F3, declared with
// its indicator 03, and 0 for Enter. An undeclared key (F12) does not end
// the screen at all, as on IBM i.

DCL-F TEST31_FKEY WORKSTN;

EXFMT FKEYTEST;

DSPLY ('RESULT:FKEY=' + %CHAR(%FKEY));
IF *IN03;
  DSPLY 'RESULT:IN03=1';
ENDIF;

*INLR = *ON;
