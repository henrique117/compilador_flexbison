/* ----------------------------------------------------
 * 1. DECLARAÇÕES E TIPOS (HEADER)
 * ---------------------------------------------------- */
%{
    #define _POSIX_C_SOURCE 200809L
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <stdbool.h>

    extern FILE *yyin;
    extern int line;
    extern int column;
    
    int yylex(void);
    void yyerror(char *s);
%}

/* Tipos visíveis no .h e no .c */
%code requires {
    typedef enum { TIPO_INT, TIPO_BOOL, TIPO_UNDEFINED } Tipo;

    typedef struct {
        Tipo type;      
        char *addr;     
    } Attributes;

    typedef struct SymbolEntry {
        char *id;
        Tipo tipo; 
        int escopo_level;
        struct SymbolEntry *next;
    } SymbolEntry;

    typedef struct Scope {
        int level;
        SymbolEntry *head;
        struct Scope *prev;
    } Scope;
}

/* Variáveis Globais e Protótipos */
%code {
    FILE *arquivo_saida = NULL; 

    Scope *current_scope = NULL;
    int scope_counter = 0;
    
    static int temp_count = 0;
    static int label_count = 0;
    
    #define MAX_STACK 100
    char* label_stack[MAX_STACK];
    int stack_top = 0;

    void push_label(char* l);
    char* pop_label(void);
    char* newTemp(void);
    char* newLabel(void);
    void emit(char *op, char *arg1, char *arg2, char *dest);
    void emitLabel(char *label);
    
    void yysemanticerror(const char *msg, int line, int column);
    void init_table(void);
    void push_scope(void);
    void pop_scope(void);
    bool check_redeclaration(const char *id);
    SymbolEntry* insert_symbol(const char *id, Tipo tipo);
    SymbolEntry* lookup_symbol(const char *id);
    const char* tipo_to_string(Tipo tipo); 
    void show_ts(void);
}

/* ----------------------------------------------------
 * 2. UNION E TOKENS
 * ---------------------------------------------------- */
%union {
    char* text;
    int val;
    Attributes info;       
    struct SymbolEntry *sym_ptr;
}

%token <text> T_ID T_NUMBER
%type <info> expr primary_expr

%token T_IF T_ELSE T_WHILE T_PRINT T_READ
%token T_TRUE T_FALSE
%token T_INT T_BOOLEAN

%token T_EQUAL T_NOT_EQUAL T_LESSER_EQUAL T_GREATER_EQUAL T_LESSER T_GREATER
%token T_AND T_OR T_NOT
%token T_ATRIBUTION
%token T_LEFT_PAREN T_RIGHT_PAREN T_LEFT_BRACKET T_RIGHT_BRACKET
%token T_SEMICOLON T_COMMA

/* --- PRECEDÊNCIA CORRIGIDA --- */
/* A ordem importa: IFX tem prioridade menor que ELSE */
%nonassoc IFX
%nonassoc T_ELSE

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
    stmt_list
    ;

stmt_list:
    stmt
    |
    stmt_list stmt
    ;

optional_stmt_list:
    
    |
    stmt_list 
    ;

compound_stmt:
    T_LEFT_BRACKET { push_scope(); } optional_stmt_list T_RIGHT_BRACKET { pop_scope(); }
    ;

/* --- AUXILIARES PARA EVITAR CONFLITOS E ARRIMAR A GERAÇÃO DE CÓDIGO --- */

/* 1. Cabeçalho do IF: Processa a condição, gera o pulo para o Falso */
if_head:
    T_IF T_LEFT_PAREN expr T_RIGHT_PAREN 
    {
        if ($3.type != TIPO_BOOL && $3.type != TIPO_UNDEFINED){
            yysemanticerror("A condicao do IF deve ser do tipo booleano.", line, column);
        }
        char *L_false = newLabel();
        emit("IF_FALSE", $3.addr, NULL, L_false);
        push_label(L_false); // Empilha para usar no fim do bloco ou no else
    }
    ;

/* 2. Inicio do While: Marca o Label de retorno */
while_start:
    T_WHILE 
    {
        char *L_start = newLabel();
        emitLabel(L_start);
        push_label(L_start);
    }
    ;

/* 3. Condição do While: Testa e pula pro fim se falso */
while_cond:
    T_LEFT_PAREN expr T_RIGHT_PAREN 
    {
        if ($2.type != TIPO_BOOL && $2.type != TIPO_UNDEFINED){
            yysemanticerror("A condicao do WHILE deve ser do tipo booleano.", line, column);
        }
        char *L_end = newLabel();
        emit("IF_FALSE", $2.addr, NULL, L_end);
        push_label(L_end);
    }
    ;


/* --- REGRA PRINCIPAL DE COMANDOS --- */
stmt:
    simple_stmt
    | compound_stmt
    
    /* Estrutura IF SEM ELSE */
    | if_head stmt %prec IFX 
      {
          char *L_false = pop_label();
          emitLabel(L_false);
      }
      
    /* Estrutura IF COM ELSE */
    | if_head stmt T_ELSE 
      {
          /* Chegamos ao fim do 'then', precisamos pular o 'else' */
          char *L_false = pop_label(); // O label que marcava o início do else
          char *L_end = newLabel();    // Novo label para o fim total
          
          emit("GOTO", NULL, NULL, L_end); // Pula o else
          emitLabel(L_false);              // Começa o else
          push_label(L_end);               // Guarda o fim total
      }
      stmt 
      {
          char *L_end = pop_label();
          emitLabel(L_end);
      }

    /* Estrutura WHILE */
    | while_start while_cond stmt 
      {
          char *L_end = pop_label();
          char *L_start = pop_label();
          emit("GOTO", NULL, NULL, L_start); // Volta para testar
          emitLabel(L_end);                  // Sai do loop
      }

    /* Tratamento de Erros de Sintaxe */
    | error T_SEMICOLON {
        yyerror("-> Erro: Ponto e virgula inesperado ou comando mal formado\n");
        yyerrok;
    }
    ;


simple_stmt:
    T_BOOLEAN T_ID T_ATRIBUTION expr T_SEMICOLON {
        if (check_redeclaration($2)) {
            yysemanticerror("Identificador re-declarado no escopo atual.", line, column);
        } else {
            insert_symbol($2, TIPO_BOOL);
            emit("ASSIGN", $4.addr, NULL, $2);
        }
    }
    | T_INT T_ID T_ATRIBUTION expr T_SEMICOLON {
        if (check_redeclaration($2)) {
            yysemanticerror("Identificador re-declarado no escopo atual.", line, column);
        } else {
            insert_symbol($2, TIPO_INT);
            emit("ASSIGN", $4.addr, NULL, $2);
      }
    }
    | T_INT T_ID T_ATRIBUTION error T_SEMICOLON {
        yyerror("-> Atribuicao invalida para int\n");
        yyerrok;
    }
    | T_BOOLEAN T_ID T_ATRIBUTION error T_SEMICOLON {
        yyerror("-> Atribuicao invalida para boolean\n");
        yyerrok;
    }
    |
    T_PRINT T_LEFT_PAREN expr T_RIGHT_PAREN T_SEMICOLON {
        emit("PRINT", NULL, NULL, $3.addr);
    }
    | T_PRINT T_LEFT_PAREN expr error T_SEMICOLON {
        yyerror("-> Detectado ')' ausente no 'print'\n");
        yyerrok;
    }
    | T_ID T_ATRIBUTION expr T_SEMICOLON {
        SymbolEntry *entry = lookup_symbol($1);
        if (entry == NULL) {
            yysemanticerror("Identificador nao declarado.", line, column);
        } else {
            if (entry->tipo != $3.type && $3.type != TIPO_UNDEFINED) {
                yysemanticerror("Tipo incompativel para atribuicao.", line, column);
            }
            emit("ASSIGN", $3.addr, NULL, $1);
        }
    }
    |
    T_READ T_LEFT_PAREN T_ID T_RIGHT_PAREN T_SEMICOLON{
        if(lookup_symbol ($3) == NULL){
            yysemanticerror("Identificador nao declarado no comando READ.", line, column);
        }
        emit("READ", NULL, NULL, $3);
    }
    ;

/* ----------------- EXPRESSÕES ----------------- */
expr:
    primary_expr { $$ = $1; } 
    |
    expr T_SUM expr {
        if ($1.type == TIPO_INT && $3.type == TIPO_INT) { 
            $$.type = TIPO_INT;
            $$.addr = newTemp();
            emit("ADD", $1.addr, $3.addr, $$.addr);
        }
        else {
            if ($1.type != TIPO_UNDEFINED && $3.type != TIPO_UNDEFINED)
                yysemanticerror("Operacao de SOMA requer dois inteiros.", line, column);
            $$.type = TIPO_UNDEFINED;
        }
    }
    |
    expr T_MINUS expr {
        if ($1.type == TIPO_INT && $3.type == TIPO_INT) { 
            $$.type = TIPO_INT;
            $$.addr = newTemp();
            emit("SUB", $1.addr, $3.addr, $$.addr);
        }
        else {
            if ($1.type != TIPO_UNDEFINED && $3.type != TIPO_UNDEFINED)
                yysemanticerror("Operacao de SUBTRACAO requer dois inteiros.", line, column);
            $$.type = TIPO_UNDEFINED;
        }
    }
    |
    expr T_MULT expr {
        if ($1.type == TIPO_INT && $3.type == TIPO_INT) { 
            $$.type = TIPO_INT;
            $$.addr = newTemp();
            emit("MUL", $1.addr, $3.addr, $$.addr);
        }
        else {
            if ($1.type != TIPO_UNDEFINED && $3.type != TIPO_UNDEFINED)
                yysemanticerror("Operacao de MULTIPLICACAO requer dois inteiros.", line, column);
            $$.type = TIPO_UNDEFINED;
        }
    }
    |
    expr T_DIV expr {
        if ($1.type == TIPO_INT && $3.type == TIPO_INT) { 
            $$.type = TIPO_INT;
            $$.addr = newTemp();
            emit("DIV", $1.addr, $3.addr, $$.addr);
        }
        else {
            if ($1.type != TIPO_UNDEFINED && $3.type != TIPO_UNDEFINED)
                yysemanticerror("Operacao de DIVISAO requer dois inteiros.", line, column);
            $$.type = TIPO_UNDEFINED;
        }
    }
    |
    expr T_AND expr {
        if ($1.type == TIPO_BOOL && $3.type == TIPO_BOOL) { 
            $$.type = TIPO_BOOL;
            $$.addr = newTemp();
            emit("AND", $1.addr, $3.addr, $$.addr);
        }
        else {
            if ($1.type != TIPO_BOOL && $3.type != TIPO_UNDEFINED)
                yysemanticerror("Operacao AND requer dois booleanos.", line, column);
            $$.type = TIPO_UNDEFINED;
        }
    }
    |
    expr T_OR expr {
        if ($1.type == TIPO_BOOL && $3.type == TIPO_BOOL) { 
            $$.type = TIPO_BOOL;
            $$.addr = newTemp();
            emit("OR", $1.addr, $3.addr, $$.addr);
        }
        else {
            if ($1.type != TIPO_BOOL && $3.type != TIPO_UNDEFINED)
                yysemanticerror("Operacao OR requer dois booleanos.", line, column);
            $$.type = TIPO_UNDEFINED;
        }
    }
    |
    T_NOT expr {
        if ($2.type == TIPO_BOOL) { 
            $$.type = TIPO_BOOL;
            $$.addr = newTemp();
            emit("NOT", $2.addr, NULL, $$.addr);
        }
        else {
            if ($2.type != TIPO_UNDEFINED)
                yysemanticerror("Operacao NOT requer um booleano.", line, column);
            $$.type = TIPO_UNDEFINED;
        }
    }
    |
    expr T_EQUAL expr {
        if ($1.type == $3.type) {
            if ($1.type != TIPO_UNDEFINED) {
                $$.type = TIPO_BOOL;
                $$.addr = newTemp();
                emit("EQ", $1.addr, $3.addr, $$.addr);
            } else {
                $$.type = TIPO_UNDEFINED;
            }
        } 
        else {
            if ($1.type != TIPO_UNDEFINED && $3.type != TIPO_UNDEFINED)
                yysemanticerror("Tipos incompativeis para comparacao (==).", line, column);
            $$.type = TIPO_UNDEFINED;
        }
    }
    |
    expr T_NOT_EQUAL expr {
        if ($1.type == $3.type) {
            if ($1.type != TIPO_UNDEFINED) {
                $$.type = TIPO_BOOL;
                $$.addr = newTemp();
                emit("NEQ", $1.addr, $3.addr, $$.addr);
            } else {
                $$.type = TIPO_UNDEFINED;
            }
        } 
        else {
            if ($1.type != TIPO_UNDEFINED && $3.type != TIPO_UNDEFINED)
                yysemanticerror("Tipos incompativeis para comparacao (!=).", line, column);
            $$.type = TIPO_UNDEFINED;
        }
    }
    |
    expr T_LESSER expr {
        if ($1.type == TIPO_INT && $3.type == TIPO_INT) { 
            $$.type = TIPO_BOOL;
            $$.addr = newTemp();
            emit("LT", $1.addr, $3.addr, $$.addr);
        }
        else {
            if ($1.type != TIPO_UNDEFINED && $3.type != TIPO_UNDEFINED)
                yysemanticerror("Comparacao (<) requer dois inteiros.", line, column);
            $$.type = TIPO_UNDEFINED;
        }
    }
    |
    expr T_GREATER expr {
        if ($1.type == TIPO_INT && $3.type == TIPO_INT) { 
            $$.type = TIPO_BOOL;
            $$.addr = newTemp();
            emit("GT", $1.addr, $3.addr, $$.addr);
        }
        else {
            if ($1.type != TIPO_UNDEFINED && $3.type != TIPO_UNDEFINED)
                yysemanticerror("Comparacao (>) requer dois inteiros.", line, column);
            $$.type = TIPO_UNDEFINED;
        }
    }
    |
    expr T_LESSER_EQUAL expr {
        if ($1.type == TIPO_INT && $3.type == TIPO_INT) { 
            $$.type = TIPO_BOOL;
            $$.addr = newTemp();
            emit("LTE", $1.addr, $3.addr, $$.addr);
        }
        else {
            if ($1.type == TIPO_UNDEFINED && $3.type == TIPO_UNDEFINED)
                yysemanticerror("Comparacao (<=) requer dois inteiros.", line, column);
            $$.type = TIPO_UNDEFINED;
        }
    }
    |
    expr T_GREATER_EQUAL expr {
        if ($1.type == TIPO_INT && $3.type == TIPO_INT) { 
            $$.type = TIPO_BOOL;
            $$.addr = newTemp();
            emit("GTE", $1.addr, $3.addr, $$.addr);
        }
        else {
            if ($1.type != TIPO_UNDEFINED && $3.type != TIPO_UNDEFINED)
                yysemanticerror("Comparacao (>=) requer dois inteiros.", line, column);
            $$.type = TIPO_UNDEFINED;
        }
    }
    |
    T_MINUS expr %prec UMINUS {
        if ($2.type == TIPO_INT) { 
            $$.type = TIPO_INT;
            $$.addr = newTemp();
            emit("MINUS_UNARY", $2.addr, NULL, $$.addr);
        }
        else {
            if ($2.type != TIPO_UNDEFINED)
                yysemanticerror("Operacao unario requer um inteiro.", line, column);
            $$.type = TIPO_UNDEFINED;
        }
    }
    |
    T_LEFT_PAREN expr T_RIGHT_PAREN {
        $$ = $2;
    }

primary_expr : 
    T_NUMBER {
        $$.type = TIPO_INT;
        $$.addr = $1; 
    }
    | T_ID {
        SymbolEntry *entry = lookup_symbol($1);
        if (entry == NULL) {
            yysemanticerror("Identificador nao declarado (uso indevido).", line, column);
            $$.type = TIPO_UNDEFINED;
        } else {
            $$.type = entry->tipo;
            $$.addr = $1;
        }
    }
    | T_TRUE {
        $$.type = TIPO_BOOL;
        $$.addr = "true";
    }
    | T_FALSE {
        $$.type = TIPO_BOOL;
        $$.addr = "false";
    }
    ;

%%
/* ----------------------------------------------------
 * 4. IMPLEMENTAÇÃO DAS FUNÇÕES (EPILOGO)
 * ---------------------------------------------------- */

void push_label(char* l) {
    if (stack_top < MAX_STACK) label_stack[stack_top++] = l;
}

char* pop_label() {
    if (stack_top > 0) return label_stack[--stack_top];
    return NULL;
}

char* newTemp() {
    char* buffer = (char*)malloc(20);
    sprintf(buffer, "t%d", temp_count++);
    return buffer;
}

char* newLabel() {
    char* buffer = (char*)malloc(20);
    sprintf(buffer, "L%d", label_count++);
    return buffer;
}

void emit(char *op, char *arg1, char *arg2, char *dest) {
    if (!arquivo_saida) arquivo_saida = stdout; 

    if (arg1 && arg2 && dest) fprintf(arquivo_saida, "\t%s %s, %s, %s\n", op, arg1, arg2, dest);
    else if (arg1 && dest)    fprintf(arquivo_saida, "\t%s %s, %s\n", op, arg1, dest);
    else if (dest)            fprintf(arquivo_saida, "\t%s %s\n", op, dest);
    else                      fprintf(arquivo_saida, "\t%s\n", op);
}

void emitLabel(char *label) {
    if (!arquivo_saida) arquivo_saida = stdout;
    fprintf(arquivo_saida, "%s:\n", label);
}

void yysemanticerror(const char *msg, int line, int column) {
    fprintf(stderr, "Erro Semantico na Linha %d, Coluna %d: %s\n", line, column, msg);
}

const char* tipo_to_string(Tipo tipo) {
    if (tipo == TIPO_INT) return "int";
    if (tipo == TIPO_BOOL) return "bool";
    return "indefinido";
}

void init_table() {
    scope_counter = 0;
    push_scope(); 
}

void push_scope() {
    Scope *new_scope = (Scope *)malloc(sizeof(Scope));
    if (!new_scope) {
        yysemanticerror("Erro interno: Memoria insuficiente.", line, column);
        exit(1);
    }
    scope_counter++;
    new_scope->level = scope_counter;
    new_scope->head = NULL;
    new_scope->prev = current_scope;
    current_scope = new_scope;
}

void pop_scope() {
    if (current_scope == NULL) return;
    Scope *old_scope = current_scope;
    current_scope = current_scope->prev;
    scope_counter--; 

    SymbolEntry *current = old_scope->head;
    SymbolEntry *next;
    while (current != NULL) {
        next = current->next;
        free(current->id);
        free(current);
        current = next;
    }
    free(old_scope);
}

bool check_redeclaration(const char *id) {
    if (current_scope == NULL) return false;
    SymbolEntry *current = current_scope->head;
    while (current != NULL) {
        if (strcmp(current->id, id) == 0) {
            return true;
        }
        current = current->next;
    }
    return false;
}

SymbolEntry* insert_symbol(const char *id, Tipo tipo) {
    if (current_scope == NULL) {
        yysemanticerror("Erro interno: Tentativa de inserir sem escopo ativo.", line, column);
        return NULL;
    }

    SymbolEntry *new_entry = (SymbolEntry *)malloc(sizeof(SymbolEntry));
    if (!new_entry) {
        yysemanticerror("Erro interno: Memoria insuficiente.", line, column);
        exit(1);
    }

    new_entry->id = strdup(id);
    new_entry->tipo = tipo;
    new_entry->escopo_level = current_scope->level;
    new_entry->next = current_scope->head;
    current_scope->head = new_entry;
    return new_entry;
}

SymbolEntry* lookup_symbol(const char *id) {
    Scope *scope = current_scope;
    while (scope != NULL) {
        SymbolEntry *current = scope->head;
        while (current != NULL) {
            if (strcmp(current->id, id) == 0) {
                return current;
            }
            current = current->next;
        }
        scope = scope->prev;
    }
    return NULL;
}

void show_ts_recursive(Scope *scope) {
    if (!scope) return;
    show_ts_recursive(scope->prev);
    printf("--- Escopo Nivel %d ---\n", scope->level);
    SymbolEntry *current = scope->head;
    int count = 1;
    while (current) {
        printf("%d. ID: %s | Tipo: %s | Nivel: %d\n", count++, current->id, tipo_to_string(current->tipo), current->escopo_level);
        current = current->next;
    }
}

void show_ts() {
    printf("\n\n=============== Tabela de Simbolos Completa ==============\n");
    show_ts_recursive(current_scope);
    printf("==========================================================\n");
}

void yyerror(char *s) {
    fprintf(stderr, "Erro Sintatico na Linha %d, Coluna %d: %s\n", line, column, s);
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Uso: %s <arquivo_entrada> [arquivo_saida]\n", argv[0]);
        return 1;
    }

    init_table();

    yyin = fopen(argv[1], "r");
    if (!yyin) {
        perror("Erro ao abrir arquivo de entrada");
        return 2;
    }

    const char* nome_saida = (argc > 2) ? argv[2] : "saida.ir";
    arquivo_saida = fopen(nome_saida, "w");
    
    if (!arquivo_saida) {
        perror("Erro ao criar arquivo de saida");
        fclose(yyin);
        return 3;
    }

    yyparse(); 

    printf("\nSucesso! Codigo intermediario gerado em: %s\n", nome_saida);
    show_ts();

    if (arquivo_saida) fclose(arquivo_saida);
    if (yyin) fclose(yyin);
    return 0;
}