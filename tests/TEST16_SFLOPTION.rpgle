**FREE
// Interactive test for subfile OPTION-field editing + validation + READC —
// see tests/run_interactive.sh. Writes 3 rows, lets the operator type an
// invalid OPTION ('9', rejected by VALUES('1' '2') via ERRSFL) then correct
// it to '2' on row 1 only, then drains the touched rows via READC.

DCL-F TEST16_SFLOPTION WORKSTN;

CUSTNO = 'CUST0001'; WRITE CUSTSFL2;
CUSTNO = 'CUST0002'; WRITE CUSTSFL2;
CUSTNO = 'CUST0003'; WRITE CUSTSFL2;

EXFMT CUSTCTL2;

DOW NOT %EOF(CUSTSFL2);
  READC CUSTSFL2;
  IF %EOF(CUSTSFL2);
    LEAVE;
  ENDIF;
  DSPLY ('RESULT:OPTION=' + OPTION);
  DSPLY ('RESULT:CUSTNO=' + CUSTNO);
ENDDO;

DSPLY 'RESULT:DONE=1';

*INLR = *ON;
