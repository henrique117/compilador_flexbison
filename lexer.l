%{
/*--------------- Definições ---------------*/
#include <stdio.h>
int line = 1;
int column = 1;
%}

digits      -?[0-9]+
letters     [a-zA-Z]+
keywords    (if|else|while|print|read|true|false)
types       (int|bool)
newline     [\n]
space       [ ]
tab         [\t]
symbols     (;|,|\(|\)|\{|\})
relop       (==|!=|<=|>=|<|>)
logicop     (&&|\|\||!)
arithop     (\+|\-|\*|\/|%)

%%
%{
    /*--------------- Regras ---------------*/
%}

{digit} { 
    printf("Digito: %s - Line: %d | Column: %d\n", yytext, line, column++);
}

{letter} {
    printf("Letra: %s - Line: %d | Column: %d\n", yytext, line, column++);
}

{keywords} {
    printf("Keyword: %s - Line: %d | Column: %d\n", yytext, line, column);
    column += strlen(yytext);
}

{types} {
    printf("Type: %s - Line: %d | Column: %d\n", yytext, line, column);
    column += strlen(yytext);
}

{symbols} {
    printf("Symbol: %s - Line: %d | Column: %d\n", yytext, line, column++);
}

{relop} {
    printf("Relational Operator: %s - Line: %d | Column: %d\n", yytext, line, column);
    column += strlen(yytext);
}

{logicop} {
    printf("Logical Operator: %s - Line: %d | Column: %d\n", yytext, line, column);
    column += strlen(yytext);
}

{arithop} {
    printf("Arithmetic Operator: %s - Line: %d | Column: %d\n", yytext, line, column++);
}

{newline}  { line++; column = 1; }
{space} { column++; }
{tab} { column += 4; }

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