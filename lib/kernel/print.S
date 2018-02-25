TI_GDT equ 0
RPL0 equ 0
SELECTOR_VIDEO equ (0x0003<<3) + TI_GDT + RPL0

[bits 32]
section .data
put_int_buffer dq 0	;定义8字节缓冲区用于数字到字符的转换
section .text
;----------------put_str--------------------------------
;put_str use put_char to print strings which end with 0
;-------------------------------------------------------
global put_str
put_str:
	push ebx
	push ecx
	xor ecx,ecx
	mov ebx,[esp+12]
.goon:
	mov cl,[ebx]
	cmp cl,0
	jz .str_over
	push ecx
	call put_char
	add esp,4
	inc ebx
	jmp .goon
.str_over:
	pop ecx
	pop ebx
	ret
;----------------put_char------------------------
;功能描述：把栈中的1个字符写入到光标所在处
;------------------------------------------------
global put_char
put_char:
	pushad 			;备份32位寄存器环境
	mov ax,SELECTOR_VIDEO 	;确保gs中为正确的视频段选择子
	mov gs,ax

;-------获取当前光标位置-------
	;先获取高8位
	mov dx,0x03d4	;索引寄存器
	mov al,0x0e	;用于提供光标位置的高8位
	out dx,al
	mov dx,0x03d5	;通过读写数据端口0x3d5来获得或设置光标位置
	in al,dx	;得到了光标位置的高8位
	mov ah,al

	;获取低8位
	mov dx,0x03d4
	mov al,0x0f
	out dx,al
	mov dx,0x03d5
	in al,dx

	;将光标存入bx
	mov bx,ax
	;下面这行在栈中获取待打印字符
	mov ecx,[esp+36]	;pushad压入32 + 主调函数返回地址4 
	cmp cl,0xd		;CR是0x0d，LF是0x0a
	jz .is_carriage_return
	cmp cl,0xa
	jz .is_line_feed

	cmp cl,0x8
	jz .is_backspace	
	jmp .put_other
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.is_backspace:
	dec bx
	shl bx,1		;光标左移一位等于乘2

	mov byte[gs:bx],0x20	;将待删除的字节补为0或者空格
	inc bx
	mov byte[gs:bx],0x07
	shr bx,1
	jmp .set_cursor
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.put_other:
	shl bx,1
	
	mov [gs:bx],cl
	inc bx
	mov byte[gs:bx],0x07
	shr bx,1
	inc bx
	cmp bx,2000
	jl .set_cursor		;若光标小于2000则设置新光标
				;超出屏幕字符数大小（2000）则换行处理

.is_line_feed:			;是换行符LF (\n)
.is_carriage_return:		;是回车符CR (\r)
	xor dx,dx
	mov ax,bx
	mov si,80

	div si

	sub bx,dx

.is_carriage_return_end:
	add bx,80
	cmp bx,2000
.is_line_feed_end:
	jl .set_cursor

;屏幕行范围是0~24，滚屏的原理是将屏幕的第1~24行搬运到第0~23行
;再将第24行用空格填充
.roll_screen:
	cld
	mov ecx,960
	mov esi,0xc00b80a0	;第1行行首
	mov edi,0xc00b8000	;第0行行首
	rep movsd

;将最后一行填充空白
	mov ebx,3840
	mov ecx,80

.cls:
	mov word [gs:ebx],0x0720 ;00720是黑底白字的空格键
	add ebx,2
	loop .cls
	mov bx,1920		 ;将光标值重置为1920，最后一行的首字符

.set_cursor:
;将光标设置为bx值
	mov dx,0x03d4
	mov al,0x0e
	out dx,al
	mov dx,0x03d5
	mov al,bh
	out dx,al

	mov dx,0x03d4
	mov al,0x0f
	out dx,al
	mov dx,0x03d5
	mov al,bl
	out dx,al
.put_char_done:
	popad
	ret

global put_int
put_int:
	pushad
	mov ebp,esp
	mov eax,[ebp+4*9]
	mov edx,eax
	mov edi,7
	mov ecx,8
	mov ebx,put_int_buffer

.16based_4bits:
	and edx,0x0000000F
	cmp edx,9
	jg .is_A2F
	add edx,'0'
	jmp .store
.is_A2F:
	sub edx,10
	add edx,'A'
.store:
	mov [ebx+edi],dl
	dec edi
	shr eax,4
	mov edx,eax
	loop .16based_4bits
.ready_to_print:
	inc edi
.skip_prefix_0:
	cmp edi,8
	je .full0
.go_on_skip:
	mov cl,[put_int_buffer+edi]
	inc edi
	cmp cl,'0'
	je .skip_prefix_0
	dec edi
	jmp .put_each_num
.full0:
	mov cl,'0'
.put_each_num:
	push ecx
	call put_char
	add esp,4
	inc edi
	mov cl,[put_int_buffer+edi]
	cmp edi,8
	jl .put_each_num
	popad
	ret

global set_cursor
set_cursor:
	pushad
	mov bx,[esp+36]
	mov dx,0x03d4
	mov al,0x0e
	out dx,al
	mov dx,0x03d5
	mov al,bh
	out dx,al

	mov dx,0x03d4
	mov al,0x0f
	out dx,al
	mov dx,0x03d5
	mov al,bl
	out dx,al
	popad
	ret
	
