**FREE
// Interactive test for DFTVAL — see tests/run_interactive.sh. Checks the
// flat RPG variables' values immediately, before ever calling EXFMT/WRITE,
// proving DFTVAL seeded them at declaration time rather than at some
// later point. SPARE1 has no DFTVAL and must stay empty — checked via a
// trailing END marker (RESULT:SPARE1=END means empty) rather than
// brackets, since the test harness's value-extraction regex only
// supports alphanumerics/./- (matching realistic RESULT: values).

DCL-F TEST21_DFTVAL WORKSTN;

DSPLY ('RESULT:GREETING=' + GREETING);
DSPLY ('RESULT:QTY=' + %CHAR(QTY));
DSPLY ('RESULT:SPARE1=' + SPARE1 + 'END');

*INLR = *ON;
