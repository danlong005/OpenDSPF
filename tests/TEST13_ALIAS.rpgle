**FREE
// Interactive test for ALIAS — the RPG program references the field as
// CUSTOMERNAME (the alias), never as CRYPTNM (the underlying DDS field
// name). See tests/run_interactive.sh.

DCL-F TEST13_ALIAS WORKSTN;

EXFMT ALIASTEST;

DSPLY ('RESULT:CUSTOMERNAME=' + CUSTOMERNAME);

*INLR = *ON;
