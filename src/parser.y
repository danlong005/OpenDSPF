%code requires {
#include "ast.h"
#include <string>
#include <vector>
}

%{
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include "ast.h"

extern int yylex();
extern int yylineno;
void yyerror(dspf::DspfFile* /*result*/, const char* msg);

static int g_error_count = 0;
int dspf_get_error_count() { return g_error_count; }

// Helper: take ownership of malloc'd string
static std::string take(char* s) { std::string r(s ? s : ""); free(s); return r; }

// Globals for accumulating the current field being parsed
static dspf::DspfField  g_field;
static std::vector<std::string> g_keywords;
static dspf::RecType    g_recType;
%}

%parse-param { dspf::DspfFile* result }

%union {
    int   ival;
    char* sval;
}

%token KW_RECORD KW_END_RECORD KW_LITERAL KW_FIELD KW_KEY KW_SCREEN KW_TITLE
%token KW_ROW KW_COL KW_SIZE KW_INDICATOR KW_COLOR KW_DSPATR KW_TEXT
%token KW_CHAR KW_ZONED KW_PACKED KW_INT
%token KW_INPUT KW_OUTPUT KW_BOTH KW_HIDDEN
%token KW_SUBFILE KW_SFLCTL KW_SFLPAG KW_SFLSIZ
%token KW_OVERLAY KW_NOCLEAR KW_ALARM KW_NOINPUT KW_PROTECT KW_WINDOW KW_WDWBORDER
%token KW_VALUES KW_RANGE KW_COMP
%token KW_STAR_CHAR KW_STAR_COLOR KW_STAR_DSPATR
%token LPAREN RPAREN COLON
%token <ival> INTEGER
%token <sval> STRING IDENTIFIER INDICATOR_REF

%type <sval> value_item value_list

%%

file
    : record_list
    ;

record_list
    : /* empty */
    | record_list record
    ;

record
    : KW_RECORD IDENTIFIER
      { g_recType = dspf::RecType::NORMAL; }
      opt_sfl_kw
      {
          result->records.emplace_back();
          result->records.back().name    = take($2);
          result->records.back().recType = g_recType;
      }
      record_body
      KW_END_RECORD
    ;

opt_sfl_kw
    : /* empty */
    | KW_SUBFILE { g_recType = dspf::RecType::SFL; }
    ;

record_body
    : /* empty */
    | record_body record_item
    ;

record_item
    : screen_clause
    | title_clause
    | literal_clause
    | field_clause
    | key_clause
    | sflctl_clause
    | sflpag_clause
    | sflsiz_clause
    | rec_kw_clause
    | window_clause
    | wdwborder_clause
    ;

screen_clause
    : KW_SCREEN KW_SIZE LPAREN INTEGER INTEGER RPAREN
      {
          result->records.back().screenRows = $4;
          result->records.back().screenCols = $5;
      }
    ;

title_clause
    : KW_TITLE STRING
      {
          result->records.back().title = take($2);
      }
    ;

literal_clause
    : KW_LITERAL KW_ROW LPAREN INTEGER RPAREN KW_COL LPAREN INTEGER RPAREN STRING
      { g_keywords.clear(); }
      opt_field_keywords
      {
          dspf::DspfLiteral lit;
          lit.row      = $4;
          lit.col      = $8;
          lit.text     = take($10);
          lit.keywords = g_keywords;
          result->records.back().literals.push_back(std::move(lit));
      }
    ;

field_clause
    : KW_FIELD IDENTIFIER
      {
          g_field = dspf::DspfField{};
          g_field.name = take($2);
          g_keywords.clear();
      }
      field_type field_usage
      KW_ROW LPAREN INTEGER RPAREN
      KW_COL LPAREN INTEGER RPAREN
      opt_field_keywords
      {
          g_field.row      = $8;
          g_field.col      = $12;
          g_field.keywords = g_keywords;
          result->records.back().fields.push_back(g_field);
      }
    ;

field_type
    : KW_CHAR LPAREN INTEGER RPAREN
      { g_field.dtype = 'A'; g_field.len = $3; g_field.dec = 0; }
    | KW_ZONED LPAREN INTEGER COLON INTEGER RPAREN
      { g_field.dtype = 'S'; g_field.len = $3; g_field.dec = $5; }
    | KW_PACKED LPAREN INTEGER COLON INTEGER RPAREN
      { g_field.dtype = 'P'; g_field.len = $3; g_field.dec = $5; }
    | KW_INT LPAREN INTEGER RPAREN
      { g_field.dtype = 'B'; g_field.len = $3; g_field.dec = 0; }
    ;

field_usage
    : KW_INPUT   { g_field.io = 'I'; }
    | KW_OUTPUT  { g_field.io = 'O'; }
    | KW_BOTH    { g_field.io = 'B'; }
    | KW_HIDDEN  { g_field.io = 'H'; }
    ;

opt_field_keywords
    : /* empty */
    | opt_field_keywords field_keyword
    ;

field_keyword
    : KW_COLOR LPAREN IDENTIFIER RPAREN
      { g_keywords.push_back("COLOR(" + take($3) + ")"); }
    | KW_DSPATR LPAREN IDENTIFIER RPAREN
      { g_keywords.push_back("DSPATR(" + take($3) + ")"); }
    | KW_TEXT LPAREN STRING RPAREN
      { g_keywords.push_back("TEXT(" + take($3) + ")"); }
    | IDENTIFIER LPAREN IDENTIFIER RPAREN
      { std::string k = take($1); g_keywords.push_back(k + "(" + take($3) + ")"); }
    | IDENTIFIER LPAREN INTEGER RPAREN
      { std::string k = take($1); g_keywords.push_back(k + "(" + std::to_string($3) + ")"); }
    | IDENTIFIER LPAREN INDICATOR_REF RPAREN
      { std::string k = take($1); g_keywords.push_back(k + "(" + take($3) + ")"); }
    | IDENTIFIER
      { g_keywords.push_back(take($1)); }
    | KW_VALUES LPAREN value_list RPAREN
      { g_keywords.push_back("VALUES(" + take($3) + ")"); }
    | KW_RANGE LPAREN value_item value_item RPAREN
      { g_keywords.push_back("RANGE(" + take($3) + " " + take($4) + ")"); }
    | KW_COMP LPAREN IDENTIFIER value_item RPAREN
      { g_keywords.push_back("COMP(" + take($3) + " " + take($4) + ")"); }
    ;

// A single VALUES/RANGE/COMP operand — quoted strings stay quoted (so the
// runtime's whitespace splitter can tell "M F" apart from unquoted M/F) and
// integers render bare.
value_item
    : STRING
      { std::string s = "'" + take($1) + "'"; $$ = strdup(s.c_str()); }
    | INTEGER
      { $$ = strdup(std::to_string($1).c_str()); }
    ;

value_list
    : value_item
      { $$ = $1; }
    | value_list value_item
      { std::string s = take($1) + " " + take($2); $$ = strdup(s.c_str()); }
    ;

sflctl_clause
    : KW_SFLCTL IDENTIFIER
      { result->records.back().recType    = dspf::RecType::SFLCTL;
        result->records.back().sflCtlFor  = take($2); }
    ;

sflpag_clause
    : KW_SFLPAG LPAREN INTEGER RPAREN
      { result->records.back().sflPag = $3; }
    ;

sflsiz_clause
    : KW_SFLSIZ LPAREN INTEGER RPAREN
      { result->records.back().sflSiz = $3; }
    ;

wdwborder_clause
    : KW_WDWBORDER LPAREN wdwborder_params RPAREN
    ;

wdwborder_params
    : /* empty */
    | wdwborder_params wdwborder_param
    ;

wdwborder_param
    : LPAREN KW_STAR_CHAR STRING RPAREN
      { result->records.back().wdwBorderChars = take($3); }
    | LPAREN KW_STAR_COLOR IDENTIFIER RPAREN
      { result->records.back().wdwBorderColor = take($3); }
    | LPAREN KW_STAR_DSPATR IDENTIFIER RPAREN
      { result->records.back().wdwBorderAttr = take($3); }
    ;

window_clause
    : KW_WINDOW LPAREN INTEGER INTEGER INTEGER INTEGER RPAREN
      {
          result->records.back().winRow    = $3;
          result->records.back().winCol    = $4;
          result->records.back().winHeight = $5;
          result->records.back().winWidth  = $6;
      }
    ;

rec_kw_clause
    : KW_OVERLAY  { result->records.back().keywords.push_back("OVERLAY"); }
    | KW_NOCLEAR  { result->records.back().keywords.push_back("NOCLEAR"); }
    | KW_ALARM    { result->records.back().keywords.push_back("ALARM"); }
    | KW_NOINPUT  { result->records.back().keywords.push_back("NOINPUT"); }
    | KW_PROTECT  { result->records.back().keywords.push_back("PROTECT"); }
    | KW_PROTECT LPAREN INDICATOR_REF RPAREN
      { result->records.back().keywords.push_back("PROTECT(" + take($3) + ")"); }
    | KW_PROTECT LPAREN IDENTIFIER RPAREN
      { result->records.back().keywords.push_back("PROTECT(" + take($3) + ")"); }
    ;

key_clause
    : KW_KEY IDENTIFIER KW_INDICATOR LPAREN INTEGER RPAREN
      {
          dspf::DspfKey k;
          k.key       = take($2);
          k.indicator = $5;
          result->records.back().keys.push_back(std::move(k));
      }
    | KW_KEY IDENTIFIER
      {
          dspf::DspfKey k;
          k.key       = take($2);
          k.indicator = 0;
          result->records.back().keys.push_back(std::move(k));
      }
    ;

%%

void yyerror(dspf::DspfFile* /*result*/, const char* msg) {
    fprintf(stderr, "dspfc: error at line %d: %s\n", yylineno, msg);
    g_error_count++;
}
