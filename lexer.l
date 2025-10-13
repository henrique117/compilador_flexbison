%{
/*--------------- INCLUDES E DEFINIÇÕES GERAIS ---------------*/
// Inclusão das bibliotecas padrão necessárias
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

digits      -?[0-9]+                         
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
symbols     (;|,|\(|\)|\{|\})
relop       (==|!=|<=|>=|<|>)
logicop     (&&|\|\||!)
arithop     (\+|\-|\*|\/|%)
id          ({letters}|[_])({letters}|{digits}|[_])*
assignment  [=]
comment     ("//".*|"/*"([^*]|\*+[^*/])*\*+"/")
error1      {digits}({letters}|[_])+

%%


{if} {
    /* Palavra reservada IF */
    printf("Keyword IF: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<IF>", yytext, line, column);
    column += strlen(yytext);
}

{else} {
    /* Palavra reservada ELSE */
    printf("Keyword ELSE: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<ELSE>", yytext, line, column);
    column += strlen(yytext);
}

{while} {
    /* Palavra reservada WHILE */
    printf("Keyword WHILE: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<WHILE>", yytext, line, column);
    column += strlen(yytext);
}

{print} {
    /* Palavra reservada PRINT */
    printf("Keyword PRINT: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<PRINT>", yytext, line, column);
    column += strlen(yytext);
}

{read} {
    /* Palavra reservada READ */
    printf("Keyword READ: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<READ>", yytext, line, column);
    column += strlen(yytext);
}

{true} {
    /* Palavra reservada TRUE */
    printf("Keyword TRUE: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<TRUE>", yytext, line, column);
    column += strlen(yytext);
}

{false} {
    /* Palavra reservada FALSE */
    printf("Keyword FALSE: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<FALSE>", yytext, line, column);
    column += strlen(yytext);
}

{types} {
    /* Tipo de dado */
    printf("Type: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<TYPE>", yytext, line, column);
    column += strlen(yytext);
}

{id} {
    /* Identificador */
    printf("ID: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<ID>", yytext, line, column);
    column += strlen(yytext);
}

{digits} { 
    /* Número inteiro */
    printf("Number: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<NUMBER>", yytext, line, column);
    column += strlen(yytext);
}

{arithop} {
    /* Operador aritmético */
    printf("Arithmetic Operator: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<ARITHOP>", yytext, line, column);
    column += strlen(yytext);
}

{relop} {
    /* Operador relacional */
    printf("Relational Operator: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<RELOP>", yytext, line, column);
    column += strlen(yytext);
}

{logicop} {
    /* Operador lógico */
    printf("Logical Operator: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<LOGICOP>", yytext, line, column);
    column += strlen(yytext);
}

{symbols} {
    /* Símbolo especial */
    printf("Symbol: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<SYMBOL>", yytext, line, column);
    column++;
}

{assignment} {
    /* Operador de atribuição */
    printf("Assignment: %s - Line: %d | Column: %d\n", yytext, line, column);
    addSymbol(&table, "<ASSIGNMENT>", yytext, line, column);
    column++;
}

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
    printf("ERRO: %s - Line: %d | Column: %d - Message: Unexpected token: \"%s\". Lexical Error.\n", yytext, line, column, yytext);
    column += strlen(yytext);
}

{error1} {
    /* Erro léxico */
    printf("ERRO: %s - Line: %d | Column: %d - Message: ID starting with a number: \"%s\". Lexical Error.\n", yytext, line, column, yytext);
    column += strlen(yytext);
}

<<EOF>> {
    /* Fim de arquivo */
    printf("Fim de arquivo - Line: %d | Column: %d\n", line, column);
    return 0;
}

%%

/*--------------- FUNÇÕES AUXILIARES E MAIN ---------------*/

// Função principal: inicializa tabela, abre arquivo, executa análise léxica e mostra tabela
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

// Função obrigatória para Flex
int yywrap() {
    return 1;
}