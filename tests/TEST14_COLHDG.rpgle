**FREE
// Interactive test for COLHDG — see tests/run_interactive.sh. NAME1's
// heading ("Name Hdg") must be painted above it; NAME2's heading
// ("Should Not Show") must be suppressed because a real LITERAL already
// sits at that position.

DCL-F TEST14_COLHDG WORKSTN;

NAME1 = 'ABC';
NAME2 = 'XYZ';
EXFMT COLHDGTEST;

DSPLY 'RESULT:DONE=1';

*INLR = *ON;
