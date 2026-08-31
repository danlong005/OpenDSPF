**FREE
// Interactive driver for TEST24_INDARA — see tests/run_interactive.sh.
// Turns *IN50 on and WRITEs the record, so the conditioned literals are
// resolved through dspf_set_indicators() with "indara": true sitting in
// the descriptor.  Proves the file-level keyword neither breaks the
// runtime's JSON reader nor disturbs indicator handling.

DCL-F TEST24_INDARA WORKSTN;

*IN50 = *ON;
WRITE INDREC;

DSPLY ('RESULT:GREETING=' + GREETING);

*INLR = *ON;
