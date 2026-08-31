**FREE
// Interactive driver for TEST25_FILEKEYS — see tests/run_interactive.sh.
// EXFMTs the record that both overrides a file-level key and inherits the
// rest, so one screen proves both directions:
//   F3  -> *IN99, the record's own CF03(99), NOT the file-level CF03(03)
//   F12 -> *IN45, the indicator the file-level CA12(45) names
//
// Every branch below is a distinct wrong answer, not just a right one. The
// runtime exits on ANY function key and falls back to returning the key's
// own number as the indicator, so *IN12 means "F12 was never declared on
// this record" — that is the reading if the file-level merge is broken, and
// it has to be distinguishable from success. *IN03 likewise means a
// file-level key leaked past a record-level override of the same name.

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
