**FREE
// Interactive test for SFLNXTCHG — see tests/run_interactive.sh.
//
// Pass 1: operator types '1' into row 1's OPTION only. The READC loop
// finds it, "detects an error" (unconditionally, for this test), and
// UPDATEs it with *IN50 (SFLNXTCHG's conditioning indicator) on — forcing
// it to be remarked as changed even though the operator won't touch it
// again.
//
// Pass 2: operator presses Enter without typing anything at all. The
// READC loop must still find row 1 — proving SFLNXTCHG resurfaced it
// purely from the program side, independent of operator input this pass.
// Row 2 was never touched by anyone and must never appear either pass.

DCL-F TEST18_SFLNXTCHG WORKSTN;

CUSTNO = 'CUST0001'; WRITE CUSTSFL4;
CUSTNO = 'CUST0002'; WRITE CUSTSFL4;

EXFMT CUSTCTL4;

READC CUSTSFL4;
DOW NOT %EOF(CUSTSFL4);
  DSPLY ('RESULT:PASS1_OPTION=' + OPTION);
  DSPLY ('RESULT:PASS1_CUSTNO=' + CUSTNO);
  *IN50 = *ON;
  UPDATE CUSTSFL4;
  *IN50 = *OFF;
  READC CUSTSFL4;
ENDDO;

EXFMT CUSTCTL4;

READC CUSTSFL4;
DOW NOT %EOF(CUSTSFL4);
  DSPLY ('RESULT:PASS2_OPTION=' + OPTION);
  DSPLY ('RESULT:PASS2_CUSTNO=' + CUSTNO);
  READC CUSTSFL4;
ENDDO;

DSPLY 'RESULT:DONE=1';

*INLR = *ON;
