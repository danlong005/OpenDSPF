**FREE
// Interactive behavioral test: CAnn and CFnn keys, as on IBM i.
//
// Pass 1: the operator types 7 into QTY (42) and presses F12, a CA key. No
// input data comes back: QTY is still 42 and CHANGE(30) stays off, though
// the key's indicator *IN12 goes on.
//
// Pass 2: the operator types 500 and presses F5, a CF key. RANGE(1 100)
// rejects it, so F5 does not end the screen; the operator corrects it to 8
// and presses F5 again. QTY is 8 and *IN30 is on, as with Enter. Before,
// every F-key returned the typed data, and none was validated.

DCL-F TEST36_CACF WORKSTN;

QTY = 42;
*IN30 = *OFF;
EXFMT ENTRY;
DSPLY ('RESULT:FKEY=' + %CHAR(%FKEY));
DSPLY ('RESULT:QTY=' + %CHAR(%INT(QTY)));
IF *IN30;
  DSPLY 'RESULT:IN30=ON';
ELSE;
  DSPLY 'RESULT:IN30=OFF';
ENDIF;
IF *IN12;
  DSPLY 'RESULT:IN12=ON';
ELSE;
  DSPLY 'RESULT:IN12=OFF';
ENDIF;

EXFMT ENTRY;
DSPLY ('RESULT:FKEY=' + %CHAR(%FKEY));
DSPLY ('RESULT:QTY=' + %CHAR(%INT(QTY)));
IF *IN30;
  DSPLY 'RESULT:IN30=ON';
ELSE;
  DSPLY 'RESULT:IN30=OFF';
ENDIF;
IF *IN12;
  DSPLY 'RESULT:IN12=ON';
ELSE;
  DSPLY 'RESULT:IN12=OFF';
ENDIF;

*INLR = *ON;
