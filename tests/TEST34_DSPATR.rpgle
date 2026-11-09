**FREE
// Interactive behavioral test for DSPATR(PC) and DSPATR(ND).
//
// USERID has DSPATR(PC), so the cursor starts there rather than on FIRST:
// the operator's XY, keyed with no Tab, lands in USERID. Tab then goes to
// PASSWD, DSPATR(ND): neither the value the program put there nor what the
// operator keys may reach the screen (checked against the raw capture in
// tests/run_interactive.sh), but the keyed value reaches the program. The
// password is compared here rather than displayed, so it never appears in
// the output at all.

DCL-F TEST34_DSPATR WORKSTN;

FIRST = 'HELLO';
PASSWD = 'TOPSECRT';
EXFMT LOGON;
DSPLY ('RESULT:USERID=' + %TRIM(USERID));
DSPLY ('RESULT:FIRST=' + %TRIM(FIRST));
IF PASSWD = 'SECRET1';
  DSPLY 'RESULT:PASSWD=OK';
ENDIF;

*INLR = *ON;
