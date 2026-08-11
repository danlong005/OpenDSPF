**FREE
// Interactive behavioral test for CLRL — see tests/run_interactive.sh.
// FIRST paints TOPLINE/MIDLINE/BOTLINE across the screen; SECOND has
// CLRL(15 20) and should only clear rows 15-20, leaving TOPLINE (row 1)
// and MIDLINE (row 10) alone.

DCL-F TEST11_CLRL WORKSTN;

WRITE FIRST;
EXFMT SECOND;

DSPLY 'RESULT:DONE=1';

*INLR = *ON;
