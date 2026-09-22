**FREE
// ─────────────────────────────────────────────────────────────────────
//  TEST28 — both-fields round trip, and a field-level DSPATR(PR).
//
//  Pass 1 (*IN04 off): the operator types over FNAME's pre-filled
//  'OLDVAL', then FCODE, then FAMT. FNAME must come back as exactly what
//  was typed — not appended to the old value — and FAMT must come back
//  at all: it sits after 11 + 4 bytes of char fields, so the buffer
//  struct pads it to offset 16 and a walker that ignores padding reads
//  and writes it in the wrong place.
//
//  Pass 2 (*IN04 on): `04 DSPATR(PR)` protects FCODE, so Tab goes from
//  FNAME straight to FAMT. If the indicator were ignored, the '5' would
//  land in FCODE and FAMT would keep pass 1's value.
// ─────────────────────────────────────────────────────────────────────

DCL-F TEST28_BFIELD WORKSTN;

FNAME = 'OLDVAL';
FCODE = 'ABC';
FAMT  = 12.50;
FOUT  = 1250.00;
*IN04 = *OFF;
EXFMT DTL;
DSPLY ('RESULT:P1NAME=' + %TRIM(FNAME));
DSPLY ('RESULT:P1CODE=' + %TRIM(FCODE));
DSPLY ('RESULT:P1AMT=' + %CHAR(%INT(FAMT * 100)));

FCODE = 'ABC';
*IN04 = *ON;
EXFMT DTL;
DSPLY ('RESULT:P2NAME=' + %TRIM(FNAME));
DSPLY ('RESULT:P2CODE=' + %TRIM(FCODE));
DSPLY ('RESULT:P2AMT=' + %CHAR(%INT(FAMT * 100)));

*INLR = *ON;
RETURN;
