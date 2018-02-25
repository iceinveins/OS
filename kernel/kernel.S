[bits 32]
%define ERROR_CODE nop	;若相关异常中cpu自动压入错误码，不做操作
%define ZERO push 0	;若相关异常中cpu没有压入错误码，压入0
extern put_str;
extern idt_table

section .data
global intr_entry_table
intr_entry_table:

%macro VECTOR 2
section .text
intr%1entry:

	%2
;以下是保存上下文环境
	push ds
	push es
	push fs
	push gs
	pushad

	;如果是从片上进入的中断，除了往片上发送EOI外，还要往主片上发送EOI
	mov al,0x20	;中断结束命令EOI
	out 0xa0,al	;向从片发送
	out 0x20,al	;向主片发送

	push %1		;一律压入中断向量号
	call [idt_table + %1*4]
	jmp intr_exit

section .data
	dd intr%1entry
%endmacro

section .text
global intr_exit
intr_exit:
;以下是恢复上下文环境
	add esp,4	;跳过中断号
	popad
	pop gs
	pop fs
	pop es
	pop ds
	add esp,4	;跳过error_code
	iretd
	
VECTOR 0x00,ZERO
VECTOR 0x01,ZERO
VECTOR 0x02,ZERO
VECTOR 0x03,ZERO
VECTOR 0x04,ZERO
VECTOR 0x05,ZERO
VECTOR 0x06,ZERO
VECTOR 0x07,ZERO
VECTOR 0x08,ERROR_CODE
VECTOR 0x09,ZERO
VECTOR 0x0a,ERROR_CODE
VECTOR 0x0b,ERROR_CODE
VECTOR 0x0c,ERROR_CODE
VECTOR 0x0d,ERROR_CODE
VECTOR 0x0e,ERROR_CODE
VECTOR 0x0f,ZERO
VECTOR 0x10,ZERO
VECTOR 0x11,ERROR_CODE
VECTOR 0x12,ZERO
VECTOR 0x13,ZERO
VECTOR 0x14,ZERO
VECTOR 0x15,ZERO
VECTOR 0x16,ZERO
VECTOR 0x17,ZERO
VECTOR 0x18,ZERO
VECTOR 0x19,ZERO
VECTOR 0x1a,ZERO
VECTOR 0x1b,ZERO
VECTOR 0x1c,ZERO
VECTOR 0x1d,ZERO
VECTOR 0x1e,ERROR_CODE
VECTOR 0x1f,ZERO
VECTOR 0x20,ZERO
