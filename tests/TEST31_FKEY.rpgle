**FREE
// Interactive behavioral test for %FKEY, an OpenRPG extension: the number
// of the function key that ended the last EXFMT, declared on the record
// (F3, with its indicator 03) or not (F12), and 0 for Enter.

DCL-F TEST31_FKEY WORKSTN;

EXFMT FKEYTEST;

DSPLY ('RESULT:FKEY=' + %CHAR(%FKEY));
IF *IN03;
  DSPLY 'RESULT:IN03=1';
ENDIF;

*INLR = *ON;
