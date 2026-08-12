**FREE
// Backward-compat check for the pre-editing row-selection subfile
// pattern, and — now that HIDDEN fields carry a real value through the
// buffer — proof that SFLRCDNBR HIDDEN is actually readable back after
// EXFMT, the classic "which row did the operator pick" mechanism. See
// tests/run_interactive.sh.

DCL-F TEST17_SFLSELECT WORKSTN;

CUSTNO = 'CUST0001'; WRITE CUSTSFL3;
CUSTNO = 'CUST0002'; WRITE CUSTSFL3;
CUSTNO = 'CUST0003'; WRITE CUSTSFL3;

EXFMT CUSTCTL3;

DSPLY ('RESULT:SFLRCDNBR=' + %CHAR(SFLRCDNBR));

*INLR = *ON;
