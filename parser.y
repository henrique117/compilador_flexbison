/* ----------------------------------------------------
 * 1. INCLUDES E DECLARAÇÕES C
 * ---------------------------------------------------- */
%{
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <stdbool.h>

    extern FILE *yyin;
    int yylex(void);
    void yyerror(char *s);
    
    extern int line;
    extern int column;

    // NOVO ENUMERADOR DE TIPOS SEMÂNTICOS
    typedef enum { TIPO_INT, TIPO_BOOL, TIPO_UNDEFINED } Tipo;

    // ESTRUTURAS DA TABELA DE SÍMBOLOS (TS) com Escopos Aninhados
    
    // Entrada de Símbolo: Armazena id, tipo e nível de escopo.
    typedef struct SymbolEntry {
        char *id;
        Tipo tipo; 
        int escopo_level;
        struct SymbolEntry *next; // Lista de símbolos do escopo
    } SymbolEntry;

    // Escopo: Nó na pilha de escopos.
    typedef struct Scope {
        int level; // Nível do escopo (1 = global, 2 = primeiro bloco, etc.)
        SymbolEntry *head; // Cabeça da lista de símbolos deste escopo
        struct Scope *prev; // Escopo anterior (simula a pilha)
    } Scope;

    // Variáveis globais da TS
    Scope *current_scope = NULL;
    int scope_counter = 0; // Contador de nível de escopo

    // PROTÓTIPOS DA TS E ERRO SEMÂNTICO
    void yysemanticerror(const char *msg, int line, int column);
    void init_table();
    void push_scope();
    void pop_scope();
    bool check_redeclaration(const char *id);
    SymbolEntry* insert_symbol(const char *id, Tipo tipo);
    SymbolEntry* lookup_symbol(const char *id);
    const char* tipo_to_string(Tipo tipo); 
    void show_ts(); // Função para exibir a tabela

%}
/* ----------------------------------------------------
 * 2. DEFINIÇÕES DOS TOKENS, TIPOS E PRECEDÊNCIAS
 * ---------------------------------------------------- */
%union {
    char* text;
    int val;
    Tipo sem_type;          // Tipo semântico (TIPO_INT, TIPO_BOOL)
    SymbolEntry *sym_ptr;   // Ponteiro para a entrada da TS (para IDs ou expressões resolvidas)
}

%token <text> T_ID T_NUMBER

// Adiciona o novo tipo semântico para expressões
%type <sem_type> expr primary_expr

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

%nonassoc IFX  /* Define a precedência para 'if' sem 'else' */
%nonassoc T_ELSE /* Define a precedência para 'else' */

%%
/* ----------------------------------------------------
 * 3. REGRAS GRAMATICAIS 
 * ---------------------------------------------------- */

program:
    stmt_list
    ;

/* A REGRA 'line' FOI COMPLETAMENTE REMOVIDA */

stmt_list:
    stmt
    | stmt_list stmt
    ;

compound_stmt:
    T_LEFT_BRACKET  { push_scope(); } T_RIGHT_BRACKET { pop_scope(); }
    |
    T_LEFT_BRACKET { push_scope(); } stmt_list T_RIGHT_BRACKET { pop_scope(); }
    | T_LEFT_BRACKET { push_scope(); } error T_RIGHT_BRACKET {
        yyerror("-> Erro de sintaxe dentro do bloco '{ }'\n");
        yyerrok;
        pop_scope(); // Garante o fechamento do escopo mesmo no erro
    }
    ;

stmt:
    matched_stmt
    | open_stmt
    | error T_SEMICOLON {
        yyerror("-> Expressao ou atribuicao mal formada\n");
        yyerrok;
    }
    | T_LEFT_BRACKET stmt_list error {
        yyerror("-> Detectado '}' ausente\n");
        yyerrok;
    }
    ;

matched_stmt:
    simple_stmt
    | compound_stmt
    | T_IF T_LEFT_PAREN expr T_RIGHT_PAREN matched_stmt T_ELSE matched_stmt
    | error T_ELSE matched_stmt {
        yyerror("-> 'else' sem 'if' previamente\n");
        yyerrok;
    }
    | T_WHILE T_LEFT_PAREN expr T_RIGHT_PAREN matched_stmt
    | T_WHILE T_LEFT_PAREN expr error matched_stmt {
        yyerror("-> Detectado ')' ausente na formacao de 'while'\n");
        yyerrok;
    }
    | T_WHILE error expr T_RIGHT_PAREN matched_stmt {
        yyerror("-> Detectado '(' ausente na formacao de 'while'\n");
        yyerrok;
    }
    ;

open_stmt:
    T_IF T_LEFT_PAREN expr T_RIGHT_PAREN stmt
    | T_IF T_LEFT_PAREN expr T_RIGHT_PAREN matched_stmt T_ELSE open_stmt
    | T_IF T_LEFT_PAREN expr error stmt {
        yyerror("-> Detectado ')' ausente no 'if'\n");
        yyerrok;
    }
    | T_IF error expr T_RIGHT_PAREN stmt {
        yyerror("-> Detectado '(' ausente no 'if'\n");
        yyerrok;
    }
    ;

simple_stmt:
    T_BOOLEAN T_ID T_ATRIBUTION expr T_SEMICOLON {
        // ID: $2.text, Tipo: TIPO_BOOL
        if (check_redeclaration($2.text)) {
            yysemanticerror("Identificador re-declarado no escopo atual.", line, column);
        } else {
            insert_symbol($2.text, TIPO_BOOL);
        }
    }
    | T_INT T_ID T_ATRIBUTION expr T_SEMICOLON {
        // ID: $2.text, Tipo: TIPO_INT
        if (check_redeclaration($2.text)) {
            yysemanticerror("Identificador re-declarado no escopo atual.", line, column);
        } else {
            insert_symbol($2.text, TIPO_INT);
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
    | T_PRINT T_LEFT_PAREN expr T_RIGHT_PAREN T_SEMICOLON
    | T_PRINT T_LEFT_PAREN expr error T_SEMICOLON {
        yyerror("-> Detectado ')' ausente no 'print'\n");
        yyerrok;
    }
    | T_ID T_ATRIBUTION expr T_SEMICOLON
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
    | T_NOT expr {
        // Propaga o valor semântico (tipo) da expressão interna ($2)
        $$ = $2; 
    }
    /* Relacionais */
    | expr T_EQUAL expr
    | expr T_NOT_EQUAL expr
    | expr T_LESSER expr
    | expr T_GREATER expr
    | expr T_LESSER_EQUAL expr
    | expr T_GREATER_EQUAL expr
    /* Unario */
    | T_MINUS expr %prec UMINUS {
        // Propaga o valor semântico (tipo) da expressão interna ($2)
        $$ = $2; 
    }
    /* Parenteses */
    | T_LEFT_PAREN expr T_RIGHT_PAREN {
        // Propaga o valor semântico (tipo) da expressão interna ($2)
        $$ = $2;
    }

primary_expr : 
    T_NUMBER {
        // Um número literal sempre tem o tipo INT
        $$.sem_type = TIPO_INT; 
    }
    | T_ID {
        SymbolEntry *entry = lookup_symbol($1.text);
        
        if (entry == NULL) {
            // ERRO SEMÂNTICO: Identificador em uso não foi declarado.
            yysemanticerror("Identificador não declarado (uso indevido).", line, column);
            
            // Para permitir que o Type Checker continue, definimos um tipo indefinido
            $$.sem_type = TIPO_UNDEFINED;
        } else {
            // ID encontrado: armazenamos o tipo da variável para uso no Type Checking
            $$.sem_type = entry->tipo;
        }
    }
    | T_TRUE {
        // 'true' é um literal booleano
        $$.sem_type = TIPO_BOOL;
    }
    | T_FALSE {
        // 'false' é um literal booleano
        $$.sem_type = TIPO_BOOL;
    }
    ;

%%
/* ----------------------------------------------------
 * 4. CÓDIGO MAIN EM C E FUNÇÃO DE ERRO
 * ---------------------------------------------------- */

void yysemanticerror(const char *msg, int line, int column) {
    fprintf(stderr, "Erro Semântico na Linha %d, Coluna %d: %s\n", line, column, msg);
}

const char* tipo_to_string(Tipo tipo) {
    if (tipo == TIPO_INT) return "int";
    if (tipo == TIPO_BOOL) return "bool";
    return "indefinido";
}

// Inicializa a tabela (cria o escopo global)
void init_table() {
    // Escopo Global (Nível 1)
    scope_counter = 0; 
    push_scope(); 
}

// Adiciona um novo escopo ao topo da pilha
void push_scope() {
    Scope *new_scope = (Scope *)malloc(sizeof(Scope));
    if (!new_scope) {
        yysemanticerror("Erro interno: Memória insuficiente para novo escopo.", line, column);
        exit(1);
    }
    scope_counter++;
    new_scope->level = scope_counter;
    new_scope->head = NULL;
    new_scope->prev = current_scope;
    current_scope = new_scope;
}

// Remove o escopo do topo da pilha e libera a memória
void pop_scope() {
    if (current_scope == NULL) return; 

    Scope *old_scope = current_scope;
    current_scope = current_scope->prev;
    scope_counter--; 

    // Libera a memória de todas as entradas de símbolo
    SymbolEntry *current = old_scope->head;
    SymbolEntry *next;
    while (current != NULL) {
        next = current->next;
        free(current->id); // Libera a string do identificador
        free(current);
        current = next;
    }
    free(old_scope);
}

// Verifica se um símbolo foi declarado *apenas* no escopo atual
bool check_redeclaration(const char *id) {
    if (current_scope == NULL) return false;
    SymbolEntry *current = current_scope->head;
    while (current != NULL) {
        if (strcmp(current->id, id) == 0) {
            return true; // Redeclaração encontrada
        }
        current = current->next;
    }
    return false;
}

// Insere um novo símbolo no escopo atual
SymbolEntry* insert_symbol(const char *id, Tipo tipo) {
    if (current_scope == NULL) {
        yysemanticerror("Erro interno: Tentativa de inserir sem escopo ativo.", line, column);
        return NULL;
    }

    SymbolEntry *new_entry = (SymbolEntry *)malloc(sizeof(SymbolEntry));
    if (!new_entry) {
        yysemanticerror("Erro interno: Memória insuficiente para nova entrada de símbolo.", line, column);
        exit(1);
    }

    new_entry->id = strdup(id);
    new_entry->tipo = tipo;
    new_entry->escopo_level = current_scope->level;

    // Insere no início da lista de símbolos do escopo atual
    new_entry->next = current_scope->head;
    current_scope->head = new_entry;
    
    return new_entry;
}

// Procura um símbolo (do escopo atual ao global)
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
        scope = scope->prev; // Desce para o escopo pai
    }
    return NULL; 
}


// Funções de exibição (substitui showTable da Fase 1)
void show_ts_recursive(Scope *scope) {
    if (!scope) return;
    
    show_ts_recursive(scope->prev); 

    printf("--- Escopo Nível %d ---\n", scope->level);
    SymbolEntry *current = scope->head;
    int count = 1;
    while (current) {
        printf("%d. ID: %s | Tipo: %s | Nível: %d\n", count++, current->id, tipo_to_string(current->tipo), current->escopo_level);
        current = current->next;
    }
}

void show_ts() {
    printf("\n\n=============== Tabela de Símbolos Completa ==============\n");
    // Iniciamos a impressão a partir do escopo atual
    show_ts_recursive(current_scope);
    printf("==========================================================\n");
}

void yyerror(char *s) {
    fprintf(stderr, "Erro Sintatico na Linha %d, Coluna %d: %s\n", line, column, s);
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Uso: %s <arquivo_de_entrada>\n", argv[0]);
        return 1;
    }

    init_table();

    yyin = fopen(argv[1], "r");
    if (!yyin) {
        perror("Erro ao abrir arquivo");
        return 2;
    }

    yyparse(); /* Inicia a analise */

    printf("\n========================================\n");
    printf("Analise sintatica concluida com sucesso!\n");
    printf("========================================\n");

    show_ts();

    fclose(yyin);
    return 0;
}