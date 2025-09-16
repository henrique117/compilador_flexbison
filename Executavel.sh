flex lexer.l
gcc lex.yy.c -o a
./a teste.txt > saida.txt