**FREE
// Interactive test proving the buffer walk correctly advances past a
// date/time/timestamp field (char[len+1] in the buffer) rather than
// treating it as a fixed-size double — see tests/run_interactive.sh.
// If dspf__extractFields/applyFields ever regress to treating L/T/Z as
// numeric (sizeof(double) instead of len+1 bytes), FLDAFTER would read
// back corrupted/misaligned data instead of what was actually typed.

DCL-F TEST12_DATETIME2 WORKSTN;

EXFMT DTINPUT;

DSPLY ('RESULT:FLDDATE=' + FLDDATE);
DSPLY ('RESULT:FLDAFTER=' + FLDAFTER);

*INLR = *ON;
