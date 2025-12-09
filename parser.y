/* ----------------------------------------------------
 * 1. DECLARAÇÕES E TIPOS (HEADER)
 * ---------------------------------------------------- */
%{
    #define _POSIX_C_SOURCE 200809L
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <stdbool.h>

    // Declarações externas vindas do Lexer (scanner.l)
    extern FILE *yyin;
    extern int line;
    extern int column;
    
    int yylex(void);
    void yyerror(char *s);
%}

/* * Bloco %code requires: 
 * Define estruturas que precisam ser visíveis tanto no .c quanto no header .h
 * Isso evita erros de "unknown type" no compilador.
 */
%code requires {
    // Enum para verificação de tipos (Semântica)
    typedef enum { TIPO_INT, TIPO_BOOL, TIPO_UNDEFINED } Tipo;

    // Estrutura que carrega dados de baixo para cima na árvore sintática
    typedef struct {
        Tipo type;      // O tipo da expressão (int ou bool)
        char *addr;     // O "endereço" (nome da variável ou temporário t1, t2...)
    } Attributes;

    // Nó da Tabela de Símbolos (Lista Ligada)
    typedef struct SymbolEntry {
        char *id;       // Nome do identificador
        Tipo tipo;      // Tipo declarado
        int escopo_level; // Nível do escopo (0=global, 1=local...)
        struct SymbolEntry *next;
    } SymbolEntry;

    // Estrutura de Escopo (Pilha de Tabelas de Símbolos)
    typedef struct Scope {
        int level;
        SymbolEntry *head; // Lista de símbolos deste escopo
        struct Scope *prev; // Ponteiro para o escopo pai (anterior)
    } Scope;
}

/* * Bloco %code: 
 * Variáveis globais e protótipos de funções auxiliares usadas nas regras.
 */
%code {
    FILE *arquivo_saida = NULL; // Ponteiro para o arquivo .ir gerado

    Scope *current_scope = NULL; // Aponta para o escopo atual (topo da pilha)
    int scope_counter = 0;       // Contador para numerar escopos
    
    // Contadores para gerar nomes únicos (t1, t2... L1, L2...)
    static int temp_count = 0;
    static int label_count = 0;
    
    // Pilha auxiliar para guardar Labels de IF/WHILE aninhados
    #define MAX_STACK 100
    char* label_stack[MAX_STACK];
    int stack_top = 0;

    // Protótipos (Implementações no final do arquivo)
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
/* A Union define os tipos de dados que os tokens e regras podem retornar ($$) */
%union {
    char* text;     // Para tokens como ID e NUMBER (texto puro)
    int val;
    Attributes info;// Para expressões (carrega tipo + endereço TAC)
    struct SymbolEntry *sym_ptr;
}

// Definição dos tokens e seus tipos na Union
%token <text> T_ID T_NUMBER
%type <info> expr primary_expr // Expressões retornam a struct Attributes

%token T_IF T_ELSE T_WHILE T_PRINT T_READ
%token T_TRUE T_FALSE
%token T_INT T_BOOLEAN

%token T_EQUAL T_NOT_EQUAL T_LESSER_EQUAL T_GREATER_EQUAL T_LESSER T_GREATER
%token T_AND T_OR T_NOT
%token T_ATRIBUTION
%token T_LEFT_PAREN T_RIGHT_PAREN T_LEFT_BRACKET T_RIGHT_BRACKET
%token T_SEMICOLON T_COMMA

/* Precedência para resolver conflitos (ex: Dangling Else) */
%nonassoc IFX       // Prioridade menor
%nonassoc T_ELSE    // Prioridade maior (força empilhar o else)

%left T_OR
%left T_AND
%nonassoc T_EQUAL T_NOT_EQUAL
%nonassoc T_LESSER T_GREATER T_LESSER_EQUAL T_GREATER_EQUAL
%left T_SUM T_MINUS
%left T_MULT T_DIV T_MOD
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

/* Bloco de código { ... }: Cria novo escopo ao entrar, remove ao sair */
compound_stmt:
    T_LEFT_BRACKET { push_scope(); } optional_stmt_list T_RIGHT_BRACKET { pop_scope(); }
    ;

/* --- REGRAS AUXILIARES PARA GERAÇÃO DE CÓDIGO (FIX PARA CONFLITOS) --- */

/* * if_head: Regra que processa o início do IF.
 * Ação: Verifica se a condição é booleana, gera Label falso e emite IF_FALSE.
 * Retorna o fluxo já preparado para o bloco 'then'.
 */
if_head:
    T_IF T_LEFT_PAREN expr T_RIGHT_PAREN 
    {
        if ($3.type != TIPO_BOOL && $3.type != TIPO_UNDEFINED){
            yysemanticerror("A condicao do IF deve ser do tipo booleano.", line, column);
        }
        char *L_false = newLabel();
        emit("IF_FALSE", $3.addr, NULL, L_false);
        push_label(L_false); // Guarda o destino do salto condicional
    }
    ;

/* while_start: Marca o início do loop para poder voltar com GOTO depois */
while_start:
    T_WHILE 
    {
        char *L_start = newLabel();
        emitLabel(L_start);
        push_label(L_start);
    }
    ;

/* while_cond: Avalia a condição de parada do loop */
while_cond:
    T_LEFT_PAREN expr T_RIGHT_PAREN 
    {
        if ($2.type != TIPO_BOOL && $2.type != TIPO_UNDEFINED){
            yysemanticerror("A condicao do WHILE deve ser do tipo booleano.", line, column);
        }
        char *L_end = newLabel();
        emit("IF_FALSE", $2.addr, NULL, L_end); // Se falso, pula para o fim
        push_label(L_end);
    }
    ;


/* --- REGRA PRINCIPAL DE COMANDOS --- */
stmt:
    simple_stmt
    | compound_stmt
    
    /* IF sem ELSE: Usa precedência IFX para resolver conflito */
    | if_head stmt %prec IFX 
      {
          char *L_false = pop_label();
          emitLabel(L_false); // Define o alvo do salto caso a condição falhe
      }
      
    /* IF com ELSE */
    | if_head stmt T_ELSE 
      {
          /* Terminamos o bloco THEN. Precisamos pular o ELSE. */
          char *L_false = pop_label(); // Recupera label do IF_FALSE
          char *L_end = newLabel();    // Cria label para o fim total
          
          emit("GOTO", NULL, NULL, L_end); // Pula o else
          emitLabel(L_false);              // Marca início do else
          push_label(L_end);               // Guarda o fim para depois do stmt do else
      }
      stmt 
      {
          char *L_end = pop_label();
          emitLabel(L_end); // Marca o fim total da estrutura
      }

    /* WHILE */
    | while_start while_cond stmt 
      {
          char *L_end = pop_label();
          char *L_start = pop_label();
          emit("GOTO", NULL, NULL, L_start); // Volta para o início (loop)
          emitLabel(L_end);                  // Marca a saída
      }

    /* Recuperação de Erro Simples (Pânico) */
    | error T_SEMICOLON {
        yyerror("-> Erro: Ponto e virgula inesperado ou comando mal formado\n");
        yyerrok;
    }
    ;

/* Comandos Simples (Atribuição, Print, Read) */
simple_stmt:
    /* Declaração e Atribuição de Booleano */
    T_BOOLEAN T_ID T_ATRIBUTION expr T_SEMICOLON {
        if (check_redeclaration($2)) {
            yysemanticerror("Identificador re-declarado no escopo atual.", line, column);
        } else {
            insert_symbol($2, TIPO_BOOL); // Insere na tabela
            emit("ASSIGN", $4.addr, NULL, $2); // Gera código: ASSIGN temp, id
        }
    }
    /* Declaração e Atribuição de Inteiro */
    | T_INT T_ID T_ATRIBUTION expr T_SEMICOLON {
        if (check_redeclaration($2)) {
            yysemanticerror("Identificador re-declarado no escopo atual.", line, column);
        } else {
            insert_symbol($2, TIPO_INT);
            emit("ASSIGN", $4.addr, NULL, $2);
      }
    }
    /* Tratamento de erros de atribuição inválida */
    | T_INT T_ID T_ATRIBUTION error T_SEMICOLON {
        yyerror("-> Atribuicao invalida para int\n");
        yyerrok;
    }
    | T_BOOLEAN T_ID T_ATRIBUTION error T_SEMICOLON {
        yyerror("-> Atribuicao invalida para boolean\n");
        yyerrok;
    }
    /* Comando PRINT */
    | T_PRINT T_LEFT_PAREN expr T_RIGHT_PAREN T_SEMICOLON {
        // Gera código: PRINT valor
        emit("PRINT", NULL, NULL, $3.addr);
    }
    /* Erro no PRINT */
    | T_PRINT T_LEFT_PAREN expr error T_SEMICOLON {
        yyerror("-> Detectado ')' ausente no 'print'\n");
        yyerrok;
    }
    /* Atribuição Simples (variável já existente) */
    | T_ID T_ATRIBUTION expr T_SEMICOLON {
        SymbolEntry *entry = lookup_symbol($1); // Busca na tabela
        if (entry == NULL) {
            yysemanticerror("Identificador nao declarado.", line, column);
        } else {
            // Checagem de Tipos
            if (entry->tipo != $3.type && $3.type != TIPO_UNDEFINED) {
                yysemanticerror("Tipo incompativel para atribuicao.", line, column);
            }
            emit("ASSIGN", $3.addr, NULL, $1);
        }
    }
    /* Comando READ */
    | T_READ T_LEFT_PAREN T_ID T_RIGHT_PAREN T_SEMICOLON{
        if(lookup_symbol ($3) == NULL){
            yysemanticerror("Identificador nao declarado no comando READ.", line, column);
        }
        emit("READ", NULL, NULL, $3);
    }
    ;

/* ----------------- EXPRESSÕES ----------------- */
/* * Regras de expressão matemática e lógica.
 * Ação Padrão: 
 * 1. Verifica compatibilidade de tipos.
 * 2. Gera novo temporário (newTemp).
 * 3. Emite a instrução (ADD, SUB, etc).
 * 4. Sobe o tipo e o endereço (t1) para a regra pai ($$).
 */
expr:
    primary_expr { $$ = $1; } 
    |
    expr T_SUM expr {
        if ($1.type == TIPO_INT && $3.type == TIPO_INT) { 
            $$.type = TIPO_INT;
            $$.addr = newTemp(); // Cria tX
            emit("ADD", $1.addr, $3.addr, $$.addr); // ADD t1, t2, tX
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
    expr T_MOD expr {
        if ($1.type == TIPO_INT && $3.type == TIPO_INT) { 
            $$.type = TIPO_INT;
            $$.addr = newTemp();
            emit("MOD", $1.addr, $3.addr, $$.addr);
        }
        else {
            if ($1.type != TIPO_UNDEFINED && $3.type != TIPO_UNDEFINED)
                yysemanticerror("Operacao de RESTO (MOD) requer dois inteiros.", line, column);
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
        if ($1.type == TIPO_INT && $3.type == TIPO_INT) {
            $$.type = TIPO_BOOL;
            $$.addr = newTemp();
            emit("EQ", $1.addr, $3.addr, $$.addr);
        } 
        else {
            if ($1.type != TIPO_UNDEFINED && $3.type != TIPO_UNDEFINED)
                yysemanticerror("Operacao relacional (==) aceita apenas inteiros.", line, column);
            $$.type = TIPO_UNDEFINED;
        }
    }
    |
    expr T_NOT_EQUAL expr {
        if ($1.type == TIPO_INT && $3.type == TIPO_INT) {
            $$.type = TIPO_BOOL;
            $$.addr = newTemp();
            emit("NEQ", $1.addr, $3.addr, $$.addr);
        } 
        else {
            if ($1.type != TIPO_UNDEFINED && $3.type != TIPO_UNDEFINED)
                yysemanticerror("Operacao relacional (!=) aceita apenas inteiros.", line, column);
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
        $$.addr = $1; // O endereço é o próprio número literal
    }
    | T_ID {
        SymbolEntry *entry = lookup_symbol($1);
        if (entry == NULL) {
            yysemanticerror("Identificador nao declarado (uso indevido).", line, column);
            $$.type = TIPO_UNDEFINED;
        } else {
            $$.type = entry->tipo;
            $$.addr = $1; // O endereço é o nome da variável
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

// Gerenciamento de Pilha de Labels (para aninhamento de if/while)
void push_label(char* l) {
    if (stack_top < MAX_STACK) label_stack[stack_top++] = l;
}

char* pop_label() {
    if (stack_top > 0) return label_stack[--stack_top];
    return NULL;
}

// Cria novo temporário: t0, t1, t2...
char* newTemp() {
    char* buffer = (char*)malloc(20);
    sprintf(buffer, "t%d", temp_count++);
    return buffer;
}

// Cria novo rótulo: L0, L1, L2...
char* newLabel() {
    char* buffer = (char*)malloc(20);
    sprintf(buffer, "L%d", label_count++);
    return buffer;
}

// Função Principal de Emissão: Escreve no arquivo ou na tela
// Formato: OP arg1, arg2, dest
void emit(char *op, char *arg1, char *arg2, char *dest) {
    if (!arquivo_saida) arquivo_saida = stdout; 

    if (arg1 && arg2 && dest) fprintf(arquivo_saida, "\t%s %s, %s, %s\n", op, arg1, arg2, dest);
    else if (arg1 && dest)    fprintf(arquivo_saida, "\t%s %s, %s\n", op, arg1, dest);
    else if (dest)            fprintf(arquivo_saida, "\t%s %s\n", op, dest);
    else                      fprintf(arquivo_saida, "\t%s\n", op);
}

// Emite um rótulo (ex: "L1:")
void emitLabel(char *label) {
    if (!arquivo_saida) arquivo_saida = stdout;
    fprintf(arquivo_saida, "%s:\n", label);
}

// Reporta erro semântico com linha e coluna
void yysemanticerror(const char *msg, int line, int column) {
    fprintf(stderr, "Erro Semantico na Linha %d, Coluna %d: %s\n", line, column, msg);
}

// Helper para converter enum Tipo em string (debug)
const char* tipo_to_string(Tipo tipo) {
    if (tipo == TIPO_INT) return "int";
    if (tipo == TIPO_BOOL) return "bool";
    return "indefinido";
}

// Inicializa a tabela de símbolos (cria escopo global)
void init_table() {
    scope_counter = 0;
    push_scope(); 
}

// Cria novo escopo e o coloca no topo da pilha (ex: entrar em função ou bloco)
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

// Remove o escopo atual (sair de bloco) e libera memória dos símbolos
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

// Verifica se ID já existe no escopo *atual* (para evitar redeclaração)
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

// Insere símbolo no escopo atual
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

// Busca símbolo em todos os escopos (do atual até o global)
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

// Exibe a tabela de símbolos recursivamente (do global para o local)
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

// Wrapper para exibir a tabela completa
void show_ts() {
    printf("\n\n=============== Tabela de Simbolos Completa ==============\n");
    show_ts_recursive(current_scope);
    printf("==========================================================\n");
}

// Reporta erro sintático
void yyerror(char *s) {
    fprintf(stderr, "Erro Sintatico na Linha %d, Coluna %d: %s\n", line, column, s);
}

// Função Main: Configura arquivos e inicia o parser
int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Uso: %s <arquivo_entrada> [arquivo_saida]\n", argv[0]);
        return 1;
    }

    init_table(); // Cria escopo global

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

    yyparse(); // Roda o analisador

    printf("\nSucesso! Codigo intermediario gerado em: %s\n", nome_saida);
    show_ts();

    if (arquivo_saida) fclose(arquivo_saida);
    if (yyin) fclose(yyin);
    return 0;
}