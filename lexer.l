%{
/*--------------- INCLUDES E DEFINIÇÕES GERAIS ---------------*/
// Inclusão das bibliotecas padrão necessárias
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser.tab.h"

#define TOKEN_EOF "<EOF>" // Token especial para fim de arquivo

// Variáveis globais para rastrear linha e coluna do token atual
int line = 1;
int column = 1;

// Estrutura para armazenar um símbolo (token reconhecido)
typedef struct {
    char token[50];   // Nome do Token (ex: <ID>, <NUMBER>, <TYPE>)
    char value[50];   // Valor do lexema reconhecido
    int line;         // Linha onde o token foi encontrado
    int column;       // Coluna onde o token foi encontrado
} Symbol;

// Estrutura da tabela de símbolos (dinâmica)
typedef struct {
    Symbol *symbols;  // Array dinâmico de símbolos
    int size;         // Quantos símbolos já foram inseridos
    int capacity;     // Capacidade atual do array
} SymbolTable;

// Inicializa a tabela de símbolos
void initTable(SymbolTable *table) {
    table->size = 0;
    table->capacity = 2;
    table->symbols = malloc(table->capacity * sizeof(Symbol));
}

// Adiciona um símbolo à tabela, expandindo se necessário
void addSymbol(SymbolTable *table, const char *token, const char *value, int line, int column) {
    // Expande o array se necessário
    if (table->size == table->capacity) {
        table->capacity *= 2;
        table->symbols = realloc(table->symbols, table->capacity * sizeof(Symbol));
    }
    // Copia os dados do símbolo
    strcpy(table->symbols[table->size].token, token);
    strcpy(table->symbols[table->size].value, value);
    table->symbols[table->size].line = line;
    table->symbols[table->size].column = column;
    table->size++;
}

// 1 é Falsidade Ideologica e 0 é Moralmente Aceito
int findSymbol(SymbolTable *table, const char *value) {
    for (int i = 0; i < table->size; i++) {
        // Compara apenas os identificadores que já foram inseridos
        if (strcmp(table->symbols[i].token, "<ID>") == 0 && 
            strcmp(table->symbols[i].value, value) == 0) {
            return 1;
        }
    }
    return 0;
}

// Mostra todos os símbolos reconhecidos
void showTable(SymbolTable *table) {
    printf("\n---- Tabela de Simbolos ----\n");
    for (int i = 0; i < table->size; i++) {
        printf("%d Token: %s | Value: %s | Line: %d | Column: %d\n",
               i + 1,
               table->symbols[i].token,
               table->symbols[i].value,
               table->symbols[i].line,
               table->symbols[i].column);
    }
    printf("----------------------------\n");
}

// Libera a memória da tabela de símbolos
void freeTable(SymbolTable *table) {
    free(table->symbols);
    table->symbols = NULL;
    table->size = table->capacity = 0;
}

SymbolTable table; // Instância global da tabela de símbolos
%}

/*--------------- DEFINIÇÕES DE PADRÕES (EXPRESSÕES REGULARES) ---------------*/

digits      ([0-9]+)|(\-[1-9][0-9]*)
letters     [a-zA-Z]+
if          "if"
else        "else"
while       "while"
print       "print"
read        "read"
true        "true"
false       "false"
types       (int|bool)

newline     [\n]
space       [ ]
tab         [\t]

mult        (\*|\/)

id          ({letters}|[_])({letters}|{digits}|[_])*
comment     ("//".*|"/*"([^*]|\*+[^*/])*\*+"/")
error1      {digits}({letters}|[_])+

%%

{if} {
    /* Palavra reservada IF */
    column += yyleng;
    return T_IF;
}

{else} {
    /* Palavra reservada ELSE */
    column += yyleng;
    return T_ELSE;
}

{while} {
    /* Palavra reservada WHILE */
    column += yyleng;
    return T_WHILE;
}

{print} {
    /* Palavra reservada PRINT */
    column += yyleng;
    return T_PRINT;
}

{read} {
    /* Palavra reservada READ */
    column += yyleng;
    return T_READ;
}

{true} {
    /* Palavra reservada TRUE */
    column += yyleng;
    return T_TRUE;
}

{false} {
    /* Palavra reservada FALSE */
    column += yyleng;
    return T_FALSE;
}

{types} {
    /* Tipo de dado */
    column += yyleng;

    if(strcmp(yytext, "int") == 0) return T_INT;
    return T_BOOLEAN;
}

{id} {
    /* Identificador */
    if (!findSymbol(&table, yytext)) {
        addSymbol(&table, "<ID>", yytext, line, column);
    }
    column += yyleng;

    yylval.text = strdup(yytext);
    return T_ID;
}

{digits} { 
    /* Número inteiro */
    addSymbol(&table, "<NUMBER>", yytext, line, column);
    column += yyleng;

    yylval.text = strdup(yytext);
    return T_NUMBER;
}

{mult} {
    column++;
    if(strcmp(yytext, "*") == 0) return T_MULT;
    return T_DIV;
}

"+" { column++; return T_SUM; }
"-" { column++; return T_MINUS; }

"==" { column += yyleng; return T_EQUAL; }
"!=" { column += yyleng; return T_NOT_EQUAL; }
"<=" { column += yyleng; return T_LESSER_EQUAL; }
">=" { column += yyleng; return T_GREATER_EQUAL; }
"<" { column++; return T_LESSER; }
">" { column++; return T_GREATER; }

"&&" { column += yyleng; return T_AND; }
"||" { column += yyleng; return T_OR; }
"!" { column++; return T_NOT; }

"=" { column++; return T_ATRIBUTION; }

";" { column++; return T_SEMICOLON; }
"," { column++; return T_COMMA; }
"(" { column++; return T_LEFT_PAREN;}
")" { column++; return T_RIGHT_PAREN; }
"{" { column++; return T_LEFT_BRACKET; }
"}" { column++; return T_RIGHT_BRACKET; }

{comment} {
    /* Ignorando Comentários, mas contando linha */
    for (int i = 0; yytext[i] != '\0'; i++) {
        if (yytext[i] == '\n') {
            line++;
            column = 1;
        } else if (yytext[i] == '\t') {
            column += 4;
        } else {
            column++;
        }
    }
}

{newline}  { line++; column = 1; }
{space}    { column++; }
{tab}      { column += 4; }

. { 
    /* Erro léxico */
    printf("ERRO: %s - Linha: %d | Coluna: %d - Messagem: Token Inesperado: \"%s\". Lexical Error.\n", yytext, line, column, yytext);
    column += yyleng;
}

{error1} {
    /* Erro léxico */
    printf("ERRO: %s - Linha: %d | Coluna: %d - Messagem: ID começando com numero: \"%s\". Lexical Error.\n", yytext, line, column, yytext);
    column += yyleng;
}

<<EOF>> {
    /* Fim de arquivo */
    /* printf("Fim de arquivo - Linha: %d | Coluna: %d\n", line, column); */
    return 0;
}

%%

/*--------------- FUNÇÕES AUXILIARES E MAIN ---------------*/

// Função Main removida para evitar conflito com o Main do Yaac (Yacc?)

// Função obrigatória para Flex
int yywrap() {
    return 1;
}