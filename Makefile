LIBTHEORA_PREFIX=/home/ondrej/usr
test:
	gcc -I$(LIBTHEORA_PREFIX)/include -c -o test.o test.c
	gcc -L$(LIBTHEORA_PREFIX)/lib -o test test.o -ltheoradec

clean:
	rm -f test.o test
