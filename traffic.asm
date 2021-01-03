;=======================================================
; 文件名: traffic.asm
; 功能描述: 交通灯控制系统
;     8255的 B口控制数码管的段显示，
;            A口控制键盘列扫描及数码管的位驱动，
;            C口控制键盘的行扫描。
;=======================================================

IOY0         EQU   0600H          ;片选IOY0对应的端口始地址
MY8255_A     EQU   IOY0+00H*2     ;8255的A口地址
MY8255_B     EQU   IOY0+01H*2     ;8255的B口地址
MY8255_C     EQU   IOY0+02H*2     ;8255的C口地址
MY8255_CON   EQU   IOY0+03H*2     ;8255的控制寄存器地址

A8254      EQU 06C0H                          	;8254计数器0端口地址
B8254      EQU 06C2H                          	;8254计数器1端口地址
C8254      EQU 06C4H                          	;8254计数器2端口地址
CON8254    EQU 06C6H                          	;8254 控制寄存器端口地址
    
SSTACK SEGMENT STACK
	       DW 200 DUP(?)
SSTACK	ENDS		

DATA SEGMENT

	; DATBLE是 将需要输入按键的值对应需要给的显示器的值
	; 比如按键1表示的值是1 但是我们送给显示器的是06H
	; 该程序是通过判断按键按下 获取其代表的偏移量（相对于DTABLE）
	; 比如按键1的偏移量是1 我们扫描按键 得出一个值 1
	; 然后利用该值在DTABLE中找到需要输出值的对应显示代码值
	; 从B口送出去即可


	TIME_COUNT DW 0                              	;计时，单位为s

	STATE      DW ?,?,?,?                        	;每个状态的结束时间
	GREEN      DW 0AH
	YELLOW     DW 03H

	;东西：|-----------------|----|----------------------|
	;      绿 40s              黄5s       红 45s
	;南北：|----------------------|-----------------|----|
	;      红 45s                    绿  40s         黄5s

	; STATE1: PA6-PC7 绿-红
	; STATE2: PA4-PC7 黄-红
	; STATE3: PA7-PC6 红-绿
	; STATE4: PA7-PC5 红-黄
	DTABLE     DB 3FH,06H,5BH,4FH,66H,6DH,7DH,07H
	           DB 7FH,6FH,77H,7CH,39H,5EH,79H,71H

	CD         DB ?,?,?,?,?,?                    	;数码管显示缓冲区

	A_SUB      DB ?                              	;A口的PA7和PA6
	CX_SUB     DW 0                              	;存中断时的CX值，意义：时钟

	LED_A      DB 0H


DATA  	ENDS

CODE SEGMENT
	           ASSUME CS:CODE,DS:DATA
	START:     
	;===========================================
	; 初始化
	;===========================================
	           MOV    AX, DATA
	           MOV    DS, AX
	           XOR    CX,CX
	           CALL   INIT_TIME

 		
	; 把CD中的值全部初始化为00H
	; 说明初始偏移量全为0
	           MOV    SI,OFFSET CD
	           MOV    AL,00H
		
	           MOV    [SI],AL         	;清显示缓冲
	           MOV    [SI+1],AL
	           MOV    [SI+2],AL
	           MOV    [SI+3],AL
	           MOV    [SI+4],AL
	           MOV    [SI+5],AL

	; 中断向量表设置
	           PUSH   DS
	           MOV    AX, 0H
	           MOV    DS, AX
	           MOV    AX, OFFSET MIR7 	;取中断入口地址
	           MOV    SI, 003CH       	;中断矢量地址
	           MOV    [SI], AX        	;填MIR7的偏移矢量
	           MOV    AX, CS          	;段地址
	           MOV    SI, 003EH
	           MOV    [SI], AX        	;填MIR7的段地址矢量

	           MOV    AX, 0H
	           MOV    DS, AX
	           MOV    AX, OFFSET MIR6 	;取中断入口地址
	           MOV    SI, 0038H       	;中断矢量地址
	           MOV    [SI], AX        	;填MIR6的偏移矢量
	           MOV    AX, CS          	;段地址
	           MOV    SI, 003AH
	           MOV    [SI], AX        	;填MIR6的段地址矢量

	           CLI
	           POP    DS
	;初始化主片8259
	           MOV    AL, 11H
	           OUT    20H, AL         	;ICW1
	           MOV    AL, 08H
	           OUT    21H, AL         	;ICW2
	           MOV    AL, 04H
	           OUT    21H, AL         	;ICW3
	           MOV    AL, 01H
	           OUT    21H, AL         	;ICW4
	           MOV    AL, 2FH         	;OCW1
	           OUT    21H, AL
	;INIT 8255
	           MOV    DX,MY8255_CON
	           MOV    AL,81H
	           OUT    DX,AL
	;8254
	           MOV    DX, CON8254     	;8254
	           MOV    AL, 36H         	;0011 0110计数器0，方式3
	           OUT    DX, AL
	           MOV    DX, A8254
	           MOV    AL, 10H         	;03E8H  --> 1000
	           OUT    DX, AL
	           MOV    AL, 27H
	           OUT    DX, AL


	           MOV    DI,OFFSET CD+5
	           STI
	
	;===========================================
	; 主程序
	;===========================================
	BEGIN:     MOV    SI,OFFSET CD
	           MOV    AL,00H
	           MOV    [SI+4],AL
	           MOV    [SI+5],AL
	           CALL   DIS
	           CALL   CLEAR
	           JMP    BEGIN

	;===========================================
	; CLEAR 清屏子程序
	;===========================================
	;就是使得所有的灯熄灭 00H表示全不亮 瞬间 很快
	CLEAR:     MOV    DX,MY8255_B
	           MOV    AL,00H
	           OUT    DX,AL
	           RET

	;===========================================
	; DIS 显示子程序
	;===========================================
	DIS:       PUSH   AX
	           MOV    SI,OFFSET CD

	; 0DFH=1101 1111 对应PA7 PA6 PA5...PA1 PA0
	; 由电路图 得出 X1-PA0 X2-PA1.....
	; 6个显示器 从左到右依次是 X1 X2 X3... X5 X6
	; 所以 对应的PA:          PA0 PA1 PA2 PA3 PA4 PA5
	; 这里初始是0DFH   代表     1   1   1   1   1   0
	; 意思是 第六个显示 开始显示数字
	; 哈哈 这里其实是从X6到X1依次显示的
	; 每个数字显示间隔很快 我们会认为是6个数字一起显示 其实是逐个显示
	           MOV    DL,0DFH
	           MOV    AL,DL

	AGAIN:     PUSH   DX
	; 把AL送给A口 觉得开放哪个灯 （这里要看电路图 A口也控制灯的开放）
	           MOV    DX,MY8255_A

	           PUSH   AX              	;对PA7 PA6特殊处理
	           AND    AL,3FH
	           MOV    BL,[LED_A]
	           OR     AL,BL
	           OUT    DX,AL
	           POP    AX
		
	           MOV    AL,[SI]         	; 把3000H--3005H中存的偏移量（相对）取出
	           MOV    BX,OFFSET DTABLE	; 获取DTABLE的首地址
	           AND    AX,00FFH        	; 因为后面会有加法运算 先把ah清0 这样ax就是
	; al的值，防止出错
	           ADD    BX,AX           	; 获取需要的值的偏移量（这个是绝对偏移量）
	           MOV    AL,[BX]         	; 获取显示数字需要的值 例 显示0需要3FH
	
	           MOV    DX,MY8255_B     	; 送往B口 显示数字       12-1\2
	           OUT    DX,AL
	
	           CALL   DALLY           	; 延时
	           INC    SI              	; 移动SI 读取下一个偏移量
	           POP    DX
	           MOV    AL,DL           	; DL: 控制哪个灯的开放 开始是0DF 1101 1111
	; 取后6位（看电路图 只连了6根线）即01 1111
	; 赋值给AL
	           TEST   AL,01H          	; 测试AL 看是否为11 1110
	; 6个灯 一次显示需要循环6次
	; 这里第六次结束是 AL=11 1110
	; 对于灯 就是x1灯显示完（灯：X6->X1）
	           JZ     OUT1            	; 6次循环完成后 跳出
	           ROR    AL,1            	; 循环右移
	; 例 第一个灯亮 AL=01 1111
	;  则 第二个灯亮 为 10 1111
	;  所以需要循环右移
	;  反映在灯上 则是左移（不要绕进去了哦）
	           MOV    DL,AL
	           JMP    AGAIN           	; 跳回 继续显示 需循环6次
	OUT1:      POP    AX
	           RET

	;===========================================
	; DALLY子程序 延时作用 RET为子程序结束标记
	;===========================================
	DALLY:     PUSH   CX
	           MOV    CX,0006H
	T1:        MOV    AX,009FH
	T2:        DEC    AX
	           JNZ    T2
	           LOOP   T1
	           POP    CX
	           RET

	;===========================================
	; PUTBUF
	;===========================================
	; 将获得的偏移量存入CD中
	; 便于后面的显示
	; 显示其实就是从CD中读取偏移量
	; 然后在table中找到真正的值即可
	PUTBUF:    MOV    SI,DI           	;存键盘值到相应位的缓冲中
	           MOV    [SI],AL         	;先存入地址CD+5 再递减 也就是下一个存入偏移量的是CD+4
	           DEC    DI
	           MOV    AX,OFFSET CD-1
	           CMP    DI,AX
	           JNZ    GOBACK
	           MOV    DI,OFFSET CD+5
	GOBACK:    RET


	;===========================================
	; MIR7
	;===========================================
	MIR7:      
	           PUSH   AX
	           PUSH   BX
	           PUSH   CX
	           PUSH   DX
	           MOV    AX,[TIME_COUNT]
	           INC    AX
	           MOV    [TIME_COUNT],AX
	           CMP    AX,100
	           JNE    MID
			 
	           XOR    AX,AX
	           MOV    [TIME_COUNT],AX
			 
	           MOV    DX, A8254
	           MOV    AL, 10H         	;2710H  --> 1000
	           OUT    DX, AL
	           MOV    AL, 27H
	           OUT    DX, AL
	           MOV    CX,[CX_SUB]
	           CMP    CX,[STATE]
	           JL     STATE1
	           MOV    BX,[STATE+2]
	           CMP    CX,BX
	           JL     STATE2
	           MOV    BX,[STATE+4]
	           CMP    CX,BX
	           JL     JMP_STATE3
	           MOV    BX,[STATE+6]
	           CMP    CX,BX
	           JL     JMP_STATE4
	           XOR    CX,CX           	;清零
	           JMP    STATE1
           
	STATE1:    MOV    AX,0131H        	; 绿-红 A：40H C:80H
	           INT    10H
	           MOV    DX,MY8255_A
	           MOV    AL,80H
	           MOV    [LED_A],AL
	           OUT    DX,AL
	           MOV    [A_SUB],AL
	           MOV    DX,MY8255_C
	           MOV    AL,40H
	           OUT    DX,AL
	;倒计时
	           MOV    AX,[STATE]
	           SUB    AX,CX
	           MOV    BL,0AH
	           DIV    BL
	           MOV    [CD],AH         	;余数，个位
	           MOV    [CD+1],AL
	           MOV    AX,[STATE+2]
	           SUB    AX,CX
	           DIV    BL
	           MOV    [CD+2],AH
	           MOV    [CD+3],AL
			  
	           JMP    NEXT
	          
	MID:       JMP    RETURN
	JMP_STATE3:JMP    STATE3
	STATE2:    MOV    AX,0132H        	; 黄-红 A：10H C：80H
	           INT    10H
	           MOV    DX,MY8255_A
	           MOV    AL,80H
	           MOV    [LED_A],AL

	           OUT    DX,AL
	           MOV    [A_SUB],AL
	           MOV    DX,MY8255_C
	           MOV    AL,20H
	           OUT    DX,AL
	;倒计时
	           MOV    AX,[STATE+2]
	           SUB    AX,CX
	           MOV    BL,0AH
	           DIV    BL
	           MOV    [CD],AH         	;余数，个位
	           MOV    [CD+1],AL       	;余数，十位
	           MOV    AX,[STATE+2]
	           SUB    AX,CX
	           DIV    BL
	           MOV    [CD+2],AH
	           MOV    [CD+3],AL
	           JMP    NEXT

	JMP_STATE4:JMP    STATE4
	STATE3:    MOV    AX,0133H        	; 红-绿 A：80H C:40H
	           INT    10H
	           MOV    DX,MY8255_A
	           MOV    AL,40H
	           MOV    [LED_A],AL

	           OUT    DX,AL
	           MOV    [A_SUB],AL
	           MOV    DX,MY8255_C
	           MOV    AL,80H
	           OUT    DX,AL
	;倒计时
	           MOV    AX,[STATE+6]
	           SUB    AX,CX
	           MOV    BL,0AH
	           DIV    BL
	           MOV    [CD],AH         	;余数，个位
	           MOV    [CD+1],AL       	;余数，十位
	           MOV    AX,[STATE+4]
	           SUB    AX,CX
	           DIV    BL
	           MOV    [CD+2],AH
	           MOV    [CD+3],AL
	           JMP    NEXT
	STATE4:    MOV    AX,0134H        	; 红-黄 A：80H C：20H
	           INT    10H
	           MOV    DX,MY8255_A
	           MOV    AL,00H
	           MOV    [LED_A],AL
	           OUT    DX,AL
	           MOV    [A_SUB],AL
	           MOV    DX,MY8255_C
	           MOV    AL,90H
	           OUT    DX,AL
	;倒计时
	           MOV    AX,[STATE+6]
	           SUB    AX,CX
	           MOV    BL,0AH
	           DIV    BL
	           MOV    [CD],AH         	;余数，个位
	           MOV    [CD+1],AL       	;余数，十位
	           MOV    AX,[STATE+6]
	           SUB    AX,CX
	           DIV    BL
	           MOV    [CD+2],AH
	           MOV    [CD+3],AL
	           JMP    NEXT
	NEXT:      
	           INC    CX
	           MOV    [CX_SUB],CX
	RETURN:    MOV    AL, 20H
	           OUT    20H, AL         	;中断结束命令
	           POP    DX
	           POP    CX
	           POP    BX
	           POP    AX
	           IRET

	;===========================================
	; INIT_TIME 对时间设置的初始化
	;===========================================
	INIT_TIME: 
	           PUSH   AX
	           PUSH   BX
	           PUSH   CX
	           PUSH   SI
	           XOR    CX,CX
	           MOV    [CX_SUB],CX
	           MOV    [TIME_COUNT],CX
	           MOV    AX,[GREEN]
	           MOV    BX,[YELLOW]
	           MOV    SI,OFFSET STATE
	           ADD    CX,AX
	           MOV    [SI],CX
	           ADD    CX,BX
	           MOV    [SI+2],CX
	           ADD    CX,AX
	           MOV    [SI+4],CX
	           ADD    CX,BX
	           MOV    [SI+6],CX
	           ADD    CX,AX
	           MOV    [SI+8],CX
	           XOR    AX,AX
	           MOV    [TIME_COUNT],AX
	           POP    SI
	           POP    CX
	           POP    BX
	           POP    AX
	           RET
	;===========================================
	; CCSCAN 键盘扫描子程序
	;===========================================
	; 原理是 先向全部列输出低电平
	; 然后从C口读入 行电平
	; 如果没有按键按下 所有行应该均为高电平
	; 反之 若有按键按下 则开始仔细判断出到底是哪个按键按下 具体判断方法是：
	; 先向第一列输出低电平（从左到右）
	; 然后从C口读入行电平 利用 AND
	; 判断哪一行是否为低电平即可(后面为了计算方便取反了行电平)
	; 若行全为高 为开始向下一列输出低电平 循环4次即可
	CCSCAN:    MOV    AL,00H
	           MOV    DX,MY8255_A
	           OUT    DX,AL           	; 向所有列输出 低电平
	           MOV    DX,MY8255_C
	           IN     AL,DX           	;读所有行电平
		
	;原来没有任何键按下 4行全为1
	;这里取反 变成 0000 便于后面的判断
	           NOT    AL
		
	; 假设没有按键按下
	; 0000&1111=0
	; 结果为0 ZF=1
	           AND    AL,0FH
	           RET

	;=====================================
	; MIR6 中断
	;=====================================
	MIR6:      
	           CLI
	           PUSH   AX
	           PUSH   BX
	           PUSH   CX
	           PUSH   DX
	           PUSH   SI
	           PUSH   DI
	           MOV    SI,OFFSET CD
	           MOV    AL,00H
	           MOV    [SI],AL         	;清显示缓冲
	           MOV    [SI+1],AL
	           MOV    [SI+2],AL
	           MOV    [SI+3],AL
	           MOV    [SI+4],AL
	           MOV    [SI+5],AL

	           MOV    DI,OFFSET CD+5


	BEGIN2:    
	           CALL   DIS
	           CALL   CLEAR
	           CALL   CCSCAN
	           JNZ    INK1
	           JMP    BEGIN2
	INK1:      
	           CALL   DIS
	           CALL   DALLY
	           CALL   DALLY
	           CALL   CLEAR
	           CALL   CCSCAN
	           JNZ    INK2
	           JMP    BEGIN2
	INK2:      
	           MOV    CH,0FEH         	; FEH=1111 1110（对应关系：PA7 PA6..PA1 PA0 ）
	           MOV    CL,00H          	; 初始对于行的偏移量 为0
	COLUM:     
	           MOV    AL,CH
	           MOV    DX,MY8255_A
	           OUT    DX,AL
	           MOV    DX,MY8255_C
	           IN     AL,DX
	L1:        TEST   AL,01H          	;is L1?
	           JNZ    L2
	           MOV    AL,00H          	;L1
	           JMP    KCODE
	L2:        TEST   AL,02H          	;is L2?
	           JNZ    L3
	           MOV    AL,04H          	;L2
	           JMP    KCODE
	L3:        TEST   AL,04H          	;is L3?
	           JNZ    L4
	           MOV    AL,08H          	;L3
	           JMP    KCODE
	L4:        TEST   AL,08H          	;is L4?
	           JNZ    NEXT2
	           MOV    AL,0CH          	;L4
	KCODE:     ADD    AL,CL           	;得到总的偏移量
	           CMP    AL,0EH          	;取消键
	           JZ     RETURN2
	           CMP    AL,0FH          	;确定键
	           JZ     ENSURE_BTN
	SHOW:      CALL   PUTBUF
	           PUSH   AX
	KON:       CALL   DIS
	           CALL   CLEAR
	           CALL   CCSCAN
	           JNZ    KON
	           POP    AX
	NEXT2:     INC    CL              	; CL相当于 行偏移量
	           MOV    AL,CH
	           TEST   AL,08H          	; 08H=0000 1000 当AL为1111 0111 && 0000 1000 结果为0
	           JZ     KERR            	;  4次列循环结束 跳KERR
	           ROL    AL,1
	           MOV    CH,AL
	           JMP    COLUM
	KERR:      
	           JMP    BEGIN2
	RETURN2:   MOV    AL, 20H
	           OUT    20H, AL         	;中断结束命令
	           POP    DI
	           POP    SI
	           POP    DX
	           POP    CX
	           POP    BX
	           POP    AX
	           STI
	           IRET
	ENSURE_BTN:CALL   SET_TIME
	           JMP    RETURN2

	;=============================================
	; SET_TIME 设置时间子程序
	;=============================================
	SET_TIME:  
	           PUSH   AX
	           PUSH   BX
	           PUSH   CX
	           XOR    AX,AX
	           MOV    SI,OFFSET CD

	           MOV    CX,0AH
	           MOV    AL,[SI+5]       	;十位
	           MOV    BL,[SI+4]       	;个位
	           MUL    CL
	           ADD    AL,BL
	
	           MOV    [GREEN],AX

	           MOV    AL,[SI+3]       	;十位
	           MOV    BL,[SI+2]       	;个位
	           MUL    CL
	           ADD    AL,BL
	           MOV    [YELLOW],AX
	           CALL   INIT_TIME
	           
	           MOV    AL,00H
		
	           MOV    [SI],AL         	;清显示缓冲
	           MOV    [SI+1],AL
	           MOV    [SI+2],AL
	           MOV    [SI+3],AL
	           MOV    [SI+4],AL
	           MOV    [SI+5],AL
	           CALL   CLEAR
	           PUSH   CX
	           POP    BX
	           POP    AX

	           RET
			    
CODE	ENDS
		END START

