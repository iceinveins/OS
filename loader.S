%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP  equ  LOADER_BASE_ADDR

;--------构建gdt及其内部的描述符----------
GDT_BASE:	dd	0x00000000
		dd	0x00000000
CODE_DESC:	dd	0x0000FFFF
		dd	DESC_CODE_HIGH4
DATA_STACK_DESC: dd	0x0000FFFF
		 dd	DESC_DATA_HIGH4
VIDEO_DESC:	dd	0x80000007
		dd	DESC_VIDEO_HIGH4

GDT_SIZE	equ	$ - GDT_BASE
GDT_LIMIT	equ	GDT_SIZE - 1
times 60 dq 0
SELECTOR_CODE	equ	(0x0001 << 3) + TI_GDT + RPL0
SELECTOR_DATA	equ 	(0x0002 << 3) + TI_GDT + RPL0
SELECTOR_VIDEO	equ 	(0x0003 << 3) + TI_GDT + RPL0

;------内存大小--------------------------------
total_mem_bytes dd 0

gdt_ptr		dw	GDT_LIMIT
		dd	GDT_BASE

;-----------手工对齐---------------------------------------
ards_buf times 244 db 0
ards_nr dw 0		;count of 'ARDS struct' 
;------------到此处256字节---------------------------------

loader_start:
;----------------------------------------------------------
;获取内存大小
;how to use int 15h-->set  eax=0000E820h ,edx=534D4150h
	xor ebx,ebx		;ebx needed to be set 0 at first time
	mov edx,0x534d4150	;ebx wont change in the future
	mov di,ards_buf
.e820_mem_get_loop:
	mov eax,0x0000e820
	mov ecx,20		;20bytes-->size of 'ARDS struct'
	int 0x15
	jc .e820_failed_so_try_e801	;if [cf] = 1,then error happened
	add di,cx
	inc word[ards_nr]
	cmp ebx,0
	jnz .e820_mem_get_loop
	mov cx,[ards_nr]
	mov ebx,ards_buf
	xor	edx,edx
.find_max_mem_area:
	mov eax,[ebx]
	add eax,[ebx+8]
	add ebx,20
	cmp edx,eax
	jge .next_ards
	mov edx,eax
.next_ards:
	loop .find_max_mem_area
	jmp .mem_get_ok

;-----int 15h ax=e801h max-support:4G----------------------
.e820_failed_so_try_e801:
	mov ax,0xe801
	int 0x15
	jc .e801_failed_so_try88
	mov cx,0x400
	mul cx
	shl edx,16
	and eax,0x0000ffff
	or edx,eax
	add edx,0x100000
	mov esi,edx
	xor eax,eax
	mov ax,bx
	mov ecx,0x100000
	mul ecx

	add esi,eax
	mov edx,esi
	jmp .mem_get_ok

;------int 15h ah=0x88 max-support:64M---------------------
.e801_failed_so_try88:
	mov ax,0x88
	int 0x15
	jc .error_hlt
	and eax,0x0000ffff
	mov cx,0x400
	mul cx
	shl edx,16
	or edx,eax
	add edx,0x100000
.mem_get_ok:
	mov [total_mem_bytes],edx
.error_hlt:

;打开保护模式
;------------------ready to start protect mode-------------
;1.open A20
;2.load gdt
;3.set cr0-pe

	;-----------open A20----------------
	in al,0x92
	or al,0000_0010B
	out 0x92,al
	
	;-----------load gdt----------------
	lgdt [gdt_ptr]

	;-----------set cr0-pe--------------
	mov eax,cr0
	or eax,0x00000001
	mov cr0,eax

	jmp dword SELECTOR_CODE:p_mode_start

[bits 32]
p_mode_start:
	mov ax,SELECTOR_DATA
	mov ds,ax
	mov es,ax
	mov ss,ax
	mov esp,LOADER_STACK_TOP
	mov ax,SELECTOR_VIDEO
	mov gs,ax
	mov byte[gs:160],'P'	

;加载内核
;--------------load kernel------------------
	mov eax,KERNEL_START_SECTOR
	mov ebx,KERNEL_BIN_BASE_ADDR
	mov ecx,200
	call rd_disk_m_32
;开启分页机制
;-------------------------------------------
	call setup_page
	sgdt [gdt_ptr]
	mov ebx,[gdt_ptr+2]		;ebx-->gdt_base
	or dword [ebx+0x18+4],0xc0000000
	add dword [gdt_ptr+2],0xc0000000
	add esp,0xc0000000
	mov eax,PAGE_DIR_TABLE_POS
	mov cr3,eax
	mov eax,cr0
	or eax,0x80000000
	mov cr0,eax
	lgdt [gdt_ptr]
	
	
	jmp SELECTOR_CODE:enter_kernel
enter_kernel:
	call kernel_init
	mov esp,0xc009f000
	jmp KERNEL_ENTRY_POINT
	



;----------------------------------------------------------
setup_page:
	mov ecx,4096
	mov esi,0
.clear_page_dir:
	mov byte[PAGE_DIR_TABLE_POS+esi],0
	inc esi
	loop .clear_page_dir

;--------------create PDE----------------------------------
.create_pde:
	mov eax,PAGE_DIR_TABLE_POS
	add eax,0x1000
	mov ebx,eax

	or eax,PG_US_U | PG_RW_W | PG_P
	mov [PAGE_DIR_TABLE_POS+0x0],eax
	mov [PAGE_DIR_TABLE_POS+0xc00],eax
	sub eax,0x1000
	mov [PAGE_DIR_TABLE_POS+4092],eax

;---------------create PTE---------------------------------
	mov ecx,256
	mov esi,0
	mov edx,PG_US_U | PG_RW_W | PG_P
.create_pte:
	mov [ebx+esi*4],edx
	add edx,4096
	inc esi
	loop .create_pte

;--------------create kernel's page's PDE------------------
	mov eax,PAGE_DIR_TABLE_POS
	add eax,0x2000
	or eax,PG_US_U | PG_RW_W | PG_P
	mov ebx,PAGE_DIR_TABLE_POS
	mov ecx,254
	mov esi,769
.create_kernel_pde:
	mov [ebx+esi*4],eax
	inc esi
	add eax,0x1000
	loop .create_kernel_pde
	ret

;----------------------------------------------------------
;read n sector
rd_disk_m_32:
;----------------------------------------------------------
			;eax=LBA扇区号
			;ebx=将数据写入的内存地址
			;ecx=读入的扇区数
	mov esi,eax
	mov edi,ecx
;读写硬盘：
;第1步：设置要读取的扇区数
	mov dx,0x1f2
	mov al,cl
	out dx,al	;读取的扇区数

	mov eax,esi
	
;第2步：将LBA地址存入0x1f3~0x1f6
	mov dx,0x1f3
	out dx,al
	
	mov cl,8
	shr eax,cl
	mov dx,0x1f4
	out dx,al

	shr eax,cl
	mov dx,0x1f5
	out dx,al
	
	shr eax,cl
	and al,0x0f
	or al,0xe0
	mov dx,0x1f6
	out dx,al
	
;第3步：向0x1f7端口写入读命令，0x20
	mov dx,0x1f7
	mov al,0x20
	out dx,al

;第4步：检测硬盘状态
.not_ready:
	nop
	in al,dx
	and al,0x88
	cmp al,0x08
	jnz .not_ready

;第5步：从0x1f0端口读数据
	mov ax,di
	mov dx,256
	mul dx
	mov cx,ax
	mov dx,0x1f0
.go_on_read:
	in eax,dx
	mov [ebx],eax
	add ebx,4
	loop .go_on_read
	ret
	
;----------------------------------------------------------
;将kernel.bin中的segment拷贝到编译地址
kernel_init:
	xor eax,eax
	xor ebx,ebx
	xor ecx,ecx
	xor edx,edx
	
	mov dx,[KERNEL_BIN_BASE_ADDR+42];偏移文件42字节处的属性是e_phentsize
	mov ebx,[KERNEL_BIN_BASE_ADDR+28];.................属性是e_phoff
	add ebx,KERNEL_BIN_BASE_ADDR
	mov cx,[KERNEL_BIN_BASE_ADDR+44];..................属性是e_phnum
	
.each_segment:
	cmp byte[ebx + 0],PT_NULL
	je .PTNULL
	
	;为函数memcpy(dst,src,size)压入参数，从右往左
	push dword [ebx+16]	;属性是p_filesz
	mov eax,[ebx+4]		;p_offset
	add eax,KERNEL_BIN_BASE_ADDR
	push eax
	push dword [ebx+8]	;p_vaddr
	call mem_cpy
	add esp,12 		;清理栈中三个参数
.PTNULL:
	add ebx,edx
	loop .each_segment

	ret
;-----------逐字节拷贝mem_cpy(dst,src,size)----------------
mem_cpy:
	cld
	push ebp
	mov ebp,esp
	push ecx
	
	mov edi,[ebp+8]
	mov esi,[ebp+12]
	mov ecx,[ebp+16]
	rep movsb

	pop ecx
	pop ebp
	ret
