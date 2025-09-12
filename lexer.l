%{
/*--------------- Definições ---------------*/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TOKEN_EOF "<EOF>"

int line = 1;
int column = 1;

// Estrutura para um símbolo
typedef struct {
    char token[50];   // Nome do Token (ex: <ID>, <NUMBER>, <TYPE>)
    char value[50];   // Valor do lexema
    int line;         // Linha
    int column;       // Coluna
} Symbol;

// Estrutura da tabela de símbolos
typedef struct {
    Symbol *symbols;  // Array de símbolos
    int size;         // Quantos já foram inseridos
    int capacity;     // Capacidade atual
} SymbolTable;

// Inicializa a tabela
void initTable(SymbolTable *table) {
    table->size = 0;
    table->capacity = 2;
    table->symbols = malloc(table->capacity * sizeof(Symbol));
}

// Adiciona um símbolo
void addSymbol(SymbolTable *table, const char *token, const char *value, int line, int column) {
    // Aumenta se necessário
    if (table->size == table->capacity) {
        table->capacity *= 2;
        table->symbols = realloc(table->symbols, table->capacity * sizeof(Symbol));
    }

    strcpy(table->symbols[table->size].token, token);
    strcpy(table->symbols[table->size].value, value);
    table->symbols[table->size].line = line;       // agora certo: int recebe int
    table->symbols[table->size].column = column;   // idem
    table->size++;
}

// Mostra a tabela
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

// Libera memória
void freeTable(SymbolTable *table) {
    free(table->symbols);
    table->symbols = NULL;
    table->size = table->capacity = 0;
}

SymbolTable table;
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
id          {letters}({letters}|{digits})*
assignment  [=]

%%

{keywords} {
    printf("Keyword: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<KEYWORD>", yytext, line, column);
    column += strlen(yytext);
}

{types} {
    printf("Type: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<TYPE>", yytext, line, column);
    column += strlen(yytext);
}

{id} {
    printf("ID: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<ID>", yytext, line, column);
    column += strlen(yytext);
}

{digits} { 
    printf("Number: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<NUMBER>", yytext, line, column);
    column += strlen(yytext);
}

{arithop} {
    printf("Arithmetic Operator: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<ARITHOP>", yytext, line, column);
    column += strlen(yytext);
}

{relop} {
    printf("Relational Operator: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<RELOP>", yytext, line, column);
    column += strlen(yytext);
}

{logicop} {
    printf("Logical Operator: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<LOGICOP>", yytext, line, column);
    column += strlen(yytext);
}

{symbols} {
    printf("Symbol: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<SYMBOL>", yytext, line, column);
    column++;
}

{assignment} {
    printf("Assignment: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<ASSIGNMENT>", yytext, line, column);
    column++;
}

{newline}  { line++; column = 1; }
{space}    { column++; }
{tab}      { column += 4; }

. { 
    printf("ERRO: %s - Line: %d | Column: %d\n", yytext, line, column);
    column += strlen(yytext);
}

<<EOF>> {
    printf("Fim de arquivo - Line: %d | Column: %d\n", line, column);
    addSymbol(&table, TOKEN_EOF, "EOF", line, column);
    return 0;
}

%%

/*--------------- Código Auxiliar ---------------*/
int main(int argc, char *argv[]) {
    initTable(&table);

    yyin = fopen(argv[1], "r");
    if (!yyin) {
        perror("Erro ao abrir arquivo");
        return 1;
    }

    yylex();
    fclose(yyin);

    showTable(&table);
    freeTable(&table);

    return 0;
}

int yywrap() {
    return 1;
}