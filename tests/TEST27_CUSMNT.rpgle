**FREE
// ─────────────────────────────────────────────────────────────────────
//  CUSMNT — Customer file maintenance.
//
//  A full-size interactive program rather than a keyword probe: the
//  load / display / READC / act loop that essentially every subfile
//  maintenance program in a real shop is built from, driven end to end
//  by scripted keystrokes. See tests/run_interactive.sh.
//
//  A real CUSMNT reads CUSMSTL1. This corpus has no IBM i database, so
//  the master is an in-memory table — what is under test is the screen
//  and subfile machinery, not record-level access, which has its own
//  tests on the OpenRPG side.
//
//  Written with subroutines rather than subprocedures, which is both
//  what shop code of this vintage looks like and what this compiler can
//  currently run: rpgc emits every global as a local of main(), so a
//  subprocedure cannot see one (see TODO.md). A WORKSTN program is
//  nothing but globals — EXFMT and READC move data through the record
//  format's fields — so subprocedures are not usable here at all yet.
// ─────────────────────────────────────────────────────────────────────

DCL-F TEST27_CUSMNT WORKSTN;

DCL-C MaxCust 6;

DCL-DS master QUALIFIED DIM(6);
  cust    CHAR(6);
  name    CHAR(20);
  addr    CHAR(20);
  city    CHAR(15);
  state   CHAR(2);
  bal     PACKED(9:2);
  gone    CHAR(1);
END-DS;

DCL-S i        INT(5);
DCL-S k        INT(5);
DCL-S sel      INT(5);
DCL-S done     IND;

// ── Master table ────────────────────────────────────────────────────
master(1).cust = '100010'; master(1).name = 'ACME SUPPLY CO';
master(1).city = 'CEDAR RAPIDS';  master(1).state = 'IA';
master(1).bal  = 1250.00;

master(2).cust = '100020'; master(2).name = 'BRIDGEPORT TOOL';
master(2).city = 'BRIDGEPORT';    master(2).state = 'CT';
master(2).bal  = 87.45;

master(3).cust = '100030'; master(3).name = 'CENTRAL FOODS INC';
master(3).city = 'OMAHA';         master(3).state = 'NE';
master(3).bal  = 0.00;

master(4).cust = '100040'; master(4).name = 'DELTA MACHINE WKS';
master(4).city = 'MEMPHIS';       master(4).state = 'TN';
master(4).bal  = 45900.99;

master(5).cust = '100050'; master(5).name = 'EASTERN FREIGHT';
master(5).city = 'NEWARK';        master(5).state = 'NJ';
master(5).bal  = 312.08;

master(6).cust = '100060'; master(6).name = 'FARMERS COOP';
master(6).city = 'SIOUX FALLS';   master(6).state = 'SD';
master(6).bal  = 7734.20;

// ── Main loop ───────────────────────────────────────────────────────
DOU done;
  EXSR LoadSfl;

  *IN91 = *ON;
  EXFMT CUSCTL;
  *IN91 = *OFF;

  IF *IN03;
    done = *ON;
  ELSE;
    EXSR DoOpts;
  ENDIF;
ENDDO;

EXSR RptMast;
DSPLY 'RESULT:DONE=1';
*INLR = *ON;
RETURN;

// ─────────────────────────────────────────────────────────────────────
//  Load the subfile.  Writes the control record TWICE — once with
//  SFLCLR's indicator on to clear it, once after loading with it off.
//  That second write must not wipe the rows.
// ─────────────────────────────────────────────────────────────────────
BEGSR LoadSfl;
  *IN90 = *ON;
  WRITE CUSCTL;
  *IN90 = *OFF;

  FOR i = 1 TO MaxCust;
    IF master(i).gone <> 'D';
      OPT   = ' ';
      SCUST = master(i).cust;
      SNAME = master(i).name;
      SBAL  = master(i).bal;
      WRITE CUSSFL;
    ENDIF;
  ENDFOR;

  WRITE CUSCTL;
ENDSR;

BEGSR FindCus;
  sel = 0;
  FOR k = 1 TO MaxCust;
    IF master(k).cust = SCUST AND master(k).gone <> 'D';
      sel = k;
    ENDIF;
  ENDFOR;
ENDSR;

BEGSR FillDtl;
  DCUST  = master(sel).cust;
  DNAME  = master(sel).name;
  DADDR  = master(sel).addr;
  DCITY  = master(sel).city;
  DSTATE = master(sel).state;
  DBAL   = master(sel).bal;
ENDSR;

// 2=Change — the detail screen comes back with whatever the operator
// typed, and F12 must abandon it rather than write it back.
BEGSR ChgCus;
  EXSR FillDtl;
  DMODE  = 'CHANGE';
  *IN04  = *OFF;
  EXFMT CUSDTL;
  IF *IN12;
    DSPLY ('RESULT:CANCELLED=' + %TRIM(master(sel).cust));
  ELSE;
    master(sel).name  = DNAME;
    master(sel).addr  = DADDR;
    master(sel).city  = DCITY;
    master(sel).state = DSTATE;
    master(sel).bal   = DBAL;
    DSPLY ('RESULT:CHANGED=' + %TRIM(master(sel).cust));
    DSPLY ('RESULT:NEWADDR=' + %TRIM(master(sel).addr));
  ENDIF;
ENDSR;

// 5=Display — the same format. PROTECT(*IN04) makes every input field
// read-only, so one format serves both modes; that is how real DDS
// avoids maintaining two near-identical screens.
BEGSR DspCus;
  EXSR FillDtl;
  DMODE = 'DISPLAY';
  *IN04 = *ON;
  EXFMT CUSDTL;
  *IN04 = *OFF;
  DSPLY ('RESULT:DISPLAYED=' + %TRIM(master(sel).cust));
ENDSR;

BEGSR DltCus;
  master(sel).gone = 'D';
  DSPLY ('RESULT:DELETED=' + %TRIM(master(sel).cust));
ENDSR;

// ─────────────────────────────────────────────────────────────────────
//  READC returns only the rows the operator actually changed, which is
//  what makes a select list workable at all — the alternative is
//  re-reading every SFLSIZ row looking for a non-blank option.
// ─────────────────────────────────────────────────────────────────────
BEGSR DoOpts;
  READC CUSSFL;
  DOW NOT %EOF(CUSSFL);
    EXSR FindCus;
    IF sel > 0;
      SELECT;
        WHEN OPT = '2';
          EXSR ChgCus;
        WHEN OPT = '4';
          EXSR DltCus;
        WHEN OPT = '5';
          EXSR DspCus;
      ENDSL;
    ENDIF;
    READC CUSSFL;
  ENDDO;
ENDSR;

// Final state of the master, so the golden pins what the maintenance
// loop actually did, not only what the screens showed.
BEGSR RptMast;
  FOR k = 1 TO MaxCust;
    IF master(k).gone <> 'D';
      // Value is extracted as [A-Za-z0-9.-]*, so no colons or spaces.
      // Balance goes out as whole cents: %CHAR on a PACKED *subfield of a
      // DS* prints 1250.000000, because a subfield's declared scale is
      // lost in codegen (see TODO.md) — reporting cents pins the same
      // number without asserting the broken path.
      DSPLY ('RESULT:M' + %CHAR(k) + '=' + %TRIM(master(k).cust) + '-'
             + %TRIM(%CHAR(%INT(master(k).bal * 100))));
    ENDIF;
  ENDFOR;
ENDSR;
