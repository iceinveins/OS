[bits 32]
section .text
global switch_to
switch_to:
	;返回地址
	push esi
	push edi
	push ebx
	push ebp
	mov eax, [esp + 20]	;得到参数cur（PCB）
	mov [eax], esp

	;------以上是备份当前线程环境，下面是恢复下一个线程环境------
	
	mov eax, [esp+24]	;得到参数next
	mov esp, [eax]
	pop ebp
	pop ebx
	pop edi
	pop esi
	ret		;返回到上面switch_to下面那句注释的返回地址
			;未由中断进入，第一次执行时返回到kernel_thread
