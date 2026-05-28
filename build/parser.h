/* A Bison parser, made by GNU Bison 3.8.2.  */

/* Bison interface for Yacc-like parsers in C

   Copyright (C) 1984, 1989-1990, 2000-2015, 2018-2021 Free Software Foundation,
   Inc.

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <https://www.gnu.org/licenses/>.  */

/* As a special exception, you may create a larger work that contains
   part or all of the Bison parser skeleton and distribute that work
   under terms of your choice, so long as that work isn't itself a
   parser generator using the skeleton or a modified version thereof
   as a parser skeleton.  Alternatively, if you modify or redistribute
   the parser skeleton itself, you may (at your option) remove this
   special exception, which will cause the skeleton and the resulting
   Bison output files to be licensed under the GNU General Public
   License without this special exception.

   This special exception was added by the Free Software Foundation in
   version 2.2 of Bison.  */

/* DO NOT RELY ON FEATURES THAT ARE NOT DOCUMENTED in the manual,
   especially those whose name start with YY_ or yy_.  They are
   private implementation details that can be changed or removed.  */

#ifndef YY_YY_BUILD_PARSER_H_INCLUDED
# define YY_YY_BUILD_PARSER_H_INCLUDED
/* Debug traces.  */
#ifndef YYDEBUG
# define YYDEBUG 0
#endif
#if YYDEBUG
extern int yydebug;
#endif
/* "%code requires" blocks.  */
#line 1 "src/parser.y"

#include "ast.h"
#include <string>
#include <vector>

#line 55 "build/parser.h"

/* Token kinds.  */
#ifndef YYTOKENTYPE
# define YYTOKENTYPE
  enum yytokentype
  {
    YYEMPTY = -2,
    YYEOF = 0,                     /* "end of file"  */
    YYerror = 256,                 /* error  */
    YYUNDEF = 257,                 /* "invalid token"  */
    KW_RECORD = 258,               /* KW_RECORD  */
    KW_END_RECORD = 259,           /* KW_END_RECORD  */
    KW_LITERAL = 260,              /* KW_LITERAL  */
    KW_FIELD = 261,                /* KW_FIELD  */
    KW_KEY = 262,                  /* KW_KEY  */
    KW_SCREEN = 263,               /* KW_SCREEN  */
    KW_TITLE = 264,                /* KW_TITLE  */
    KW_ROW = 265,                  /* KW_ROW  */
    KW_COL = 266,                  /* KW_COL  */
    KW_SIZE = 267,                 /* KW_SIZE  */
    KW_INDICATOR = 268,            /* KW_INDICATOR  */
    KW_COLOR = 269,                /* KW_COLOR  */
    KW_DSPATR = 270,               /* KW_DSPATR  */
    KW_TEXT = 271,                 /* KW_TEXT  */
    KW_CHAR = 272,                 /* KW_CHAR  */
    KW_ZONED = 273,                /* KW_ZONED  */
    KW_PACKED = 274,               /* KW_PACKED  */
    KW_INT = 275,                  /* KW_INT  */
    KW_INPUT = 276,                /* KW_INPUT  */
    KW_OUTPUT = 277,               /* KW_OUTPUT  */
    KW_BOTH = 278,                 /* KW_BOTH  */
    KW_HIDDEN = 279,               /* KW_HIDDEN  */
    KW_SUBFILE = 280,              /* KW_SUBFILE  */
    KW_SFLCTL = 281,               /* KW_SFLCTL  */
    KW_SFLPAG = 282,               /* KW_SFLPAG  */
    KW_SFLSIZ = 283,               /* KW_SFLSIZ  */
    KW_OVERLAY = 284,              /* KW_OVERLAY  */
    KW_NOCLEAR = 285,              /* KW_NOCLEAR  */
    KW_ALARM = 286,                /* KW_ALARM  */
    KW_NOINPUT = 287,              /* KW_NOINPUT  */
    KW_PROTECT = 288,              /* KW_PROTECT  */
    LPAREN = 289,                  /* LPAREN  */
    RPAREN = 290,                  /* RPAREN  */
    COLON = 291,                   /* COLON  */
    INTEGER = 292,                 /* INTEGER  */
    STRING = 293,                  /* STRING  */
    IDENTIFIER = 294,              /* IDENTIFIER  */
    INDICATOR_REF = 295            /* INDICATOR_REF  */
  };
  typedef enum yytokentype yytoken_kind_t;
#endif

/* Value type.  */
#if ! defined YYSTYPE && ! defined YYSTYPE_IS_DECLARED
union YYSTYPE
{
#line 32 "src/parser.y"

    int   ival;
    char* sval;

#line 117 "build/parser.h"

};
typedef union YYSTYPE YYSTYPE;
# define YYSTYPE_IS_TRIVIAL 1
# define YYSTYPE_IS_DECLARED 1
#endif


extern YYSTYPE yylval;


int yyparse (dspf::DspfFile* result);


#endif /* !YY_YY_BUILD_PARSER_H_INCLUDED  */
