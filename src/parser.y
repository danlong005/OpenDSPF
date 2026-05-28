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
%token LPAREN RPAREN COLON
%token <ival> INTEGER
%token <sval> STRING IDENTIFIER

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
      {
          result->records.emplace_back();
          result->records.back().name = take($2);
      }
      record_body
      KW_END_RECORD
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
      {
          dspf::DspfLiteral lit;
          lit.row  = $4;
          lit.col  = $8;
          lit.text = take($10);
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
    | IDENTIFIER
      { g_keywords.push_back(take($1)); }
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
