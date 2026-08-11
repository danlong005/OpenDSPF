**FREE
// Interactive behavioral test for KEY PAGEUP/PAGEDOWN as exit keys on a
// plain (non-subfile) record — see tests/run_interactive.sh.

DCL-F TEST10_PAGEKEY WORKSTN;

EXFMT PAGEKEYTEST;

IF *IN21;
  DSPLY 'RESULT:KEY=PAGEUP';
ELSEIF *IN22;
  DSPLY 'RESULT:KEY=PAGEDOWN';
ELSE;
  DSPLY 'RESULT:KEY=NONE';
ENDIF;

*INLR = *ON;
