**FREE
// Interactive test for COLOR/DSPATR on LITERAL lines — see
// tests/run_interactive.sh. The check is on the raw captured terminal
// escape sequences (which color pair / attribute got applied around each
// literal's text), not any DSPLY output.

DCL-F TEST22_LITERAL_STYLE WORKSTN;

EXFMT MYREC;

DSPLY 'RESULT:DONE=1';

*INLR = *ON;
