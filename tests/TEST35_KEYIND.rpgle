**FREE
// Interactive behavioral test: which indicators an input operation touches.
//
// As on IBM i, a key's response indicator is set on when it is pressed and
// the record's other keys' indicators are set off; nothing else changes.
// KEYS declares CA03(03) and a bare CA12, which names no indicator.
//
// Pass 1, EXFMT, F12 pressed: *IN03 goes off (declared, not pressed); *IN12
// stays on, since no key names it — CA12 sets nothing, and %FKEY is 12; *IN20,
// which no key names either, stays on. Before, every indicator 01-24 was
// cleared and a bare CA12 set *IN12.
//
// Pass 2, WRITE then READ, Enter pressed: the same rule holds for READ.

DCL-F TEST35_KEYIND WORKSTN;

*IN03 = *ON;
*IN12 = *ON;
*IN20 = *ON;
EXFMT KEYS;
DSPLY ('RESULT:FKEY=' + %CHAR(%FKEY));
IF *IN03;
  DSPLY 'RESULT:IN03=ON';
ELSE;
  DSPLY 'RESULT:IN03=OFF';
ENDIF;
IF *IN12;
  DSPLY 'RESULT:IN12=ON';
ELSE;
  DSPLY 'RESULT:IN12=OFF';
ENDIF;
IF *IN20;
  DSPLY 'RESULT:IN20=ON';
ELSE;
  DSPLY 'RESULT:IN20=OFF';
ENDIF;

*IN03 = *ON;
WRITE KEYS;
READ KEYS;
IF *IN03;
  DSPLY 'RESULT:READIN03=ON';
ELSE;
  DSPLY 'RESULT:READIN03=OFF';
ENDIF;
IF *IN20;
  DSPLY 'RESULT:READIN20=ON';
ELSE;
  DSPLY 'RESULT:READIN20=OFF';
ENDIF;

*INLR = *ON;
