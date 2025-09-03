%{
/*--------------- Definições ---------------*/
#include <stdio.h>
int line = 1;
%}

digit       [0-9]
letter      [a-zA-Z]
keywords    (if|else|while|print|read|true|false)
types       (int|bool)
newline     [\n]

%%
%{
    /*--------------- Regras ---------------*/
%}

{digit}    { printf("Digito: %s - Line: %d\n", yytext, line); }
{letter}   { printf("Letra: %s - Line: %d\n", yytext, line); }
{keywords} { printf("Keyword: %s - Line: %d\n", yytext, line); }
{types}    { printf("Type: %s - Line: %d\n", yytext, line); }

{newline}  { line++; }

%%
/*--------------- Código Auxiliar ---------------*/
int main(int argc, char *argv[]) {

    yyin = fopen(argv[1], "r");
    yyout = stdout;

    yylex();
    fclose(yyin);
    return 0;
}

int yywrap() {
    return 0;
}