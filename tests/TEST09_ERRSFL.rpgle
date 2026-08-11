**FREE
// Interactive behavioral test for ERRSFL/SFLMSGRCD — see tests/run_interactive.sh.
// Two invalid attempts (X, Y) must each produce a validation error at a
// different message-subfile row (accumulating), then a valid attempt (A)
// succeeds.

DCL-F TEST09_ERRSFL WORKSTN;

EXFMT ERRTEST;

DSPLY ('RESULT:CODE=' + CODE);

*INLR = *ON;
