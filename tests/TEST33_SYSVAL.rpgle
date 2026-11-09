**FREE
// Interactive behavioral test for the DATE, TIME, USER and SYSNAME
// constants. What they show is checked against the raw screen capture in
// tests/run_interactive.sh; *IN10 conditions the second DATE.

DCL-F TEST33_SYSVAL WORKSTN;

*IN10 = *ON;
EXFMT HEADER;
DSPLY 'RESULT:DONE=1';

*INLR = *ON;
