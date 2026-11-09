**FREE
// Interactive driver for TEST25_FILEKEYS — see tests/run_interactive.sh.
// EXFMTs the record that both overrides a file-level key and inherits the
// rest, so one screen proves both directions:
//   F3  -> *IN99, the record's own CF03(99), NOT the file-level CF03(03)
//   F12 -> *IN45, the indicator the file-level CA12(45) names
//
// Every branch below is a distinct wrong answer, not just a right one.
// *IN03 means a file-level key leaked past a record-level override of the
// same name. The runtime used to exit on any function key, setting the
// key's own number as the indicator, so *IN12 meant "F12 was never
// declared"; since 2026-11-08 an undeclared key is refused, as on IBM i, so
// a broken merge now leaves the screen up until the harness times out, and
// the *IN12 branch is kept only as a guard against that fallback returning.

DCL-F TEST25_FILEKEYS WORKSTN;

EXFMT OVERRIDE;

IF *IN99;
  DSPLY 'RESULT:KEY=F3-OVERRIDE';
ELSEIF *IN03;
  DSPLY 'RESULT:KEY=F3-FILELEVEL';
ELSEIF *IN45;
  DSPLY 'RESULT:KEY=F12-INHERITED';
ELSEIF *IN12;
  DSPLY 'RESULT:KEY=F12-UNDECLARED';
ELSE;
  DSPLY 'RESULT:KEY=NONE';
ENDIF;

*INLR = *ON;
