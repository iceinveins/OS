#!/bin/sh
sudo gcc -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -o build/main.o kernel/main.c
sudo nasm -f elf32 -o bulid/print.o lib/kernel/print.S
sudo nasm -f elf32 -o bulid/kernel.o kernel/kernel.S
sudo gcc -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -o build/interrupt.o kernel/interrupt.c
sudo gcc -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -o build/init.o kernel/init.c
sudo ld -Ttext 0xc0001500 -e main -o build/kernel.bin build/main.o bulid/init.o bulid/interrupt.o build/print.o build/kernel.o
sudo dd if=build/kernel.bin of=./hd60M.img bs=512 count=200 seek=9 conv=notrunc
