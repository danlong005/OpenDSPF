**FREE
// Interactive behavioral test for the AUTO keyword — see tests/run_interactive.sh.
// FLD1 has AUTO (should auto-advance to FLD2 when filled). FLD2/FLD3 don't
// (should NOT auto-advance — cursor must be moved explicitly, e.g. via Tab).

DCL-F TEST08_AUTO WORKSTN;

EXFMT AUTOTEST;

// Prefixed so the test harness can grep these out unambiguously — raw
// terminal capture from the ncurses screen paint can otherwise contain the
// same bare characters (e.g. "ABC") as coincidental noise.
DSPLY ('RESULT:FLD1=' + FLD1);
DSPLY ('RESULT:FLD2=' + FLD2);
DSPLY ('RESULT:FLD3=' + FLD3);

*INLR = *ON;
