%{
#include <cstdlib>
#include <cstring>
#include <string>
#include "ast.h"
#include "parser.h"

static char* strip_quotes(const char* s) {
    size_t len = strlen(s);
    char* r = (char*)malloc(len);
    size_t j = 0;
    for (size_t i = 1; i < len - 1; i++) {
        if (s[i] == '\'' && i + 1 < len - 1 && s[i+1] == '\'') {
            r[j++] = '\''; i++;
        } else {
            r[j++] = s[i];
        }
    }
    r[j] = '\0';
    return r;
}
%}

%option noyywrap nounput noinput case-insensitive yylineno

IDENT    [A-Za-z_][A-Za-z0-9_\-]*
INTEGER  [0-9]+
STRING   \'([^']|\'\')*\'
WS       [ \t]+
NL       \r?\n
COMMENT  "//"[^\n]*

%%

"**FREE"        { /* free-format header — skip */ }
"**DSPF"        { /* legacy free-format header — skip */ }
{COMMENT}       { /* line comment — skip */ }
{NL}            { /* newlines — skip */ }
{WS}            { /* whitespace — skip */ }

"RECORD"        { return KW_RECORD; }
"END-RECORD"    { return KW_END_RECORD; }
"LITERAL"       { return KW_LITERAL; }
"FIELD"         { return KW_FIELD; }
"KEY"           { return KW_KEY; }
"SCREEN"        { return KW_SCREEN; }
"TITLE"         { return KW_TITLE; }

"ROW"           { return KW_ROW; }
"COL"           { return KW_COL; }
"SIZE"          { return KW_SIZE; }
"INDICATOR"     { return KW_INDICATOR; }
"COLOR"         { return KW_COLOR; }
"DSPATR"        { return KW_DSPATR; }
"TEXT"          { return KW_TEXT; }

"CHAR"          { return KW_CHAR; }
"ZONED"         { return KW_ZONED; }
"PACKED"        { return KW_PACKED; }
"INT"           { return KW_INT; }
"DATE"          { return KW_DATE; }
"TIME"          { return KW_TIME; }
"TIMESTAMP"     { return KW_TIMESTAMP; }
"INPUT"         { return KW_INPUT; }
"OUTPUT"        { return KW_OUTPUT; }
"BOTH"          { return KW_BOTH; }
"HIDDEN"        { return KW_HIDDEN; }

"SUBFILE"       { return KW_SUBFILE; }
"SFLCTL"        { return KW_SFLCTL; }
"SFLPAG"        { return KW_SFLPAG; }
"SFLSIZ"        { return KW_SFLSIZ; }

"OVERLAY"       { return KW_OVERLAY; }
"NOCLEAR"       { return KW_NOCLEAR; }
"ALARM"         { return KW_ALARM; }
"NOINPUT"       { return KW_NOINPUT; }
"PROTECT"       { return KW_PROTECT; }
"ERRSFL"        { return KW_ERRSFL; }
"SFLMSGRCD"     { return KW_SFLMSGRCD; }
"CLRL"          { return KW_CLRL; }
"CHANGE"        { return KW_CHANGE; }
"SFLNXTCHG"     { return KW_SFLNXTCHG; }
"INDTXT"        { return KW_INDTXT; }
"WINDOW"        { return KW_WINDOW; }
"WDWBORDER"     { return KW_WDWBORDER; }
"VALUES"        { return KW_VALUES; }
"RANGE"         { return KW_RANGE; }
"COMP"          { return KW_COMP; }
"*CHAR"         { return KW_STAR_CHAR; }
"*COLOR"        { return KW_STAR_COLOR; }
"*DSPATR"       { return KW_STAR_DSPATR; }

N?\*IN[0-9]+    { yylval.sval = strdup(yytext); return INDICATOR_REF; }
{INTEGER}       { yylval.ival = atoi(yytext); return INTEGER; }
{STRING}        { yylval.sval = strip_quotes(yytext); return STRING; }
{IDENT}         { yylval.sval = strdup(yytext); return IDENTIFIER; }

"("             { return LPAREN; }
")"             { return RPAREN; }
":"             { return COLON; }

.               { /* ignore unrecognised characters */ }

%%
