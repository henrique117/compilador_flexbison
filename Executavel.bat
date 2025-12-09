@echo off

echo 1. Gerando o Parser (Bison)...
win_bison -d parser.y

echo.
echo 2. Gerando o Lexer (Flex)...
win_flex lexer.l

echo.
echo 3. Compilando e Linkando (GCC)...
gcc parser.tab.c lex.yy.c -o compilador

echo.
echo Compilacao concluida!
echo Para executar, use: compilador.exe seu_arquivo_de_teste.txt