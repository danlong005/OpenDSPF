**FREE
// Backward-compat check for the pre-editing row-selection subfile
// pattern — see tests/run_interactive.sh.

DCL-F TEST17_SFLSELECT WORKSTN;

CUSTNO = 'CUST0001'; WRITE CUSTSFL3;
CUSTNO = 'CUST0002'; WRITE CUSTSFL3;
CUSTNO = 'CUST0003'; WRITE CUSTSFL3;

EXFMT CUSTCTL3;

DSPLY 'RESULT:DONE=1';

*INLR = *ON;
