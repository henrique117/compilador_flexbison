/* ----------------------------------------------------
 * 1. INCLUDES E DECLARAÇÕES C
 * ---------------------------------------------------- */
%{
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>

    extern FILE *yyin;
    int yylex(void);
    void yyerror(char *s);

    extern int line;
    extern int column;
%}
/* ----------------------------------------------------
 * 2. DEFINIÇÕES DOS TOKENS, TIPOS E PRECEDÊNCIAS
 * ---------------------------------------------------- */
%union {
    char* text;
    int val;
}

%token <text> T_ID T_NUMBER

%token T_IF T_ELSE T_WHILE T_PRINT T_READ
%token T_TRUE T_FALSE
%token T_INT T_BOOLEAN

%token T_EQUAL T_NOT_EQUAL T_LESSER_EQUAL T_GREATER_EQUAL T_LESSER T_GREATER
%token T_AND T_OR T_NOT
%token T_ATRIBUTION
%token T_LEFT_PAREN T_RIGHT_PAREN T_LEFT_BRACKET T_RIGHT_BRACKET
%token T_SEMICOLON T_COMMA

//%type <val> expr logic_or_expr logic_and_expr equality_expr relational_expr
//%type <val> additive_expr multiplicative_expr unary_expr primary_expr
//%type <val> assignment_expr

%left T_OR
%left T_AND
%nonassoc T_EQUAL T_NOT_EQUAL
%nonassoc T_LESSER T_GREATER T_LESSER_EQUAL T_GREATER_EQUAL
%left T_SUM T_MINUS
%left T_MULT T_DIV
%right T_NOT UMINUS

%%
/* ----------------------------------------------------
 * 3. REGRAS GRAMATICAIS 
 * ---------------------------------------------------- */

program:
    | program line
    ;

line:
    '\n'
    | stmt '\n'
    | T_SEMICOLON
    | error '\n'  { yyerrok; } // Adicione isso
;

stmt_list:
    /* Lista de comandos */
    | stmt_list stmt
    ;

compound_stmt:
    T_LEFT_BRACKET stmt_list T_RIGHT_BRACKET
    ;

stmt:
    matched_stmt
    | open_stmt
    ;

matched_stmt:
    simple_stmt
    | compound_stmt
    | T_IF T_LEFT_PAREN expr T_RIGHT_PAREN matched_stmt T_ELSE matched_stmt
    | T_WHILE T_LEFT_PAREN expr T_RIGHT_PAREN matched_stmt
    ;

open_stmt:
    T_IF T_LEFT_PAREN expr T_RIGHT_PAREN stmt
    | T_IF T_LEFT_PAREN expr T_RIGHT_PAREN matched_stmt T_ELSE open_stmt
    ;

simple_stmt:
    T_BOOLEAN T_ID T_ATRIBUTION expr T_SEMICOLON
    | T_INT T_ID T_ATRIBUTION expr T_SEMICOLON
    | T_ID T_ATRIBUTION expr T_SEMICOLON
    | T_PRINT T_LEFT_PAREN expr T_RIGHT_PAREN T_SEMICOLON
    | T_READ T_LEFT_PAREN T_ID T_RIGHT_PAREN T_SEMICOLON
    ;

/* ----------------- EXPRESSÕES ----------------- */
expr:
    primary_expr
    /* Aritméticos */
    | expr T_SUM expr
    | expr T_MINUS expr
    | expr T_MULT expr
    | expr T_DIV expr
    /* Logicos */
    | expr T_AND expr
    | expr T_OR expr
    | T_NOT expr
    /* Relacionais */
    | expr T_EQUAL expr
    | expr T_NOT_EQUAL expr
    | expr T_LESSER expr
    | expr T_GREATER expr
    | expr T_LESSER_EQUAL expr
    | expr T_GREATER_EQUAL expr
    /* Unario */
    | T_MINUS expr %prec UMINUS
    /* Parenteses */
    | T_LEFT_PAREN expr T_RIGHT_PAREN
    ;

primary_expr : T_NUMBER
    | T_ID
    | T_TRUE
    | T_FALSE
    ;

%%
/* ----------------------------------------------------
 * 4. CÓDIGO MAIN EM C E FUNÇÃO DE ERRO
 * ---------------------------------------------------- */
void yyerror(char *s) {
    fprintf(stderr, "Erro de Sintaxe na Linha %d, Coluna %d: %s\n", line, column, s);
} 

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Uso: %s <arquivo_de_entrada>\n", argv[0]);
        return 1;
    }

    yyin = fopen(argv[1], "r");
    if (!yyin) {
        perror("Erro ao abrir arquivo");
        return 1;
    }

    yyparse(); /* Inicia a analise */
    
    fclose(yyin);
    return 0;
}