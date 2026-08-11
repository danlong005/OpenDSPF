**FREE
// Interactive test for CHANGE and BLANKS — see tests/run_interactive.sh.
// Two EXFMT passes of the same record format prove indicators reset fresh
// each pass rather than sticking from a prior one:
//   Pass 1: FLDX is typed into ("ABC"). FLDQTY's edit buffer starts
//     pre-filled with "0" (an uninitialized RPG numeric var reads as
//     zero), so it's explicitly backspaced blank to test the real "blank"
//     case rather than an already-blank field that was never touched.
//     -> *IN67 (CHANGE) on, *IN01 (BLANKS) on.
//   Pass 2: FLDX is left untouched, FLDQTY is explicitly typed as "0".
//     -> *IN67 off (nothing keyed into FLDX this time),
//        *IN01 off (a real, keyed zero is not "blank").

DCL-F TEST15_CHANGE_BLANKS WORKSTN;

EXFMT CHGBLKTEST;
IF *IN67;
  DSPLY 'RESULT:PASS1_CHANGE=ON';
ELSE;
  DSPLY 'RESULT:PASS1_CHANGE=OFF';
ENDIF;
IF *IN01;
  DSPLY 'RESULT:PASS1_BLANKS=ON';
ELSE;
  DSPLY 'RESULT:PASS1_BLANKS=OFF';
ENDIF;

EXFMT CHGBLKTEST;
IF *IN67;
  DSPLY 'RESULT:PASS2_CHANGE=ON';
ELSE;
  DSPLY 'RESULT:PASS2_CHANGE=OFF';
ENDIF;
IF *IN01;
  DSPLY 'RESULT:PASS2_BLANKS=ON';
ELSE;
  DSPLY 'RESULT:PASS2_BLANKS=OFF';
ENDIF;

*INLR = *ON;
