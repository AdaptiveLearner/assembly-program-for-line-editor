; LINE EDITOR
; environment: MASM, DosBox
; Albert Wu, 2019.

.MODEL LARGE

.STACK 64

COLORBUFFER     EQU 0B800H      ; video buffer start address

EDITSTART       EQU 320         ; edit start offset relative to COLORBUFFER
EDITSIZE        EQU 1600        ; edit window size (bytes)

; SCAN CODE FOR KEYS
HOME_KEY        EQU 47H         ; home
UPARROW_KEY     EQU 48H         ; up arrow
LEFTARROW_KEY   EQU 4BH         ; left arrow
RIGHTARROW_KEY  EQU 4DH         ; right arrow
END_KEY         EQU 4FH         ; end
DOWNARROW_KEY   EQU 50H         ; down arrow
DEL_KEY         EQU 53H         ; delete

; ASCII CODE FOR KEYS
BACKSPACE_KEY   EQU 08H         ; backspace
TAB_KEY         EQU 09H         ; tab
ENTER_KEY       EQU 0DH         ; enter
ESC_KEY         EQU 1BH         ; escape


NDIGIT          EQU 3           ; assume: 3 digits per integer 
NDIGIT2         EQU 6           ; assume: 6 bytes per integer for video buffer
FIRST_ROW       EQU 2           ; start row for edit window
MAX_ROW         EQU 21          ; row[2..21] for edit window
NORMAL_ATTRIB   EQU 07H         ; normal char attribute for video buffer


.DATA

FUN         DB 4,'E',7,'d',7,'i',7,'t',7    ; (Edit) 7: normal char attribute
INSERT      DB 3,'I',7,'N',7,'S',7          ; (INS)
CAPSLOCK    DB 4,'C',7,'A',7,'P',7,'S',7    ; (CAPS)
NUMLOCK     DB 7,'N',7,'U',7,'M',7,'L',7,'O',7,'C',7,'K',7  ; (NUMLOCK)
BLNK        DB 7,' ',7,' ',7,' ',7,' ',7,' ',7,' ',7,' ',7  ; blanks
COMMA       DB 1,',',7                      ; comma

; constants
ROW2        DB 1        ; -------
ROW23       DB 22       ; -------

ROW24       DB 23       ; status row
ED_ROW      DB 70       ; line position
ED_COMMA    DB 73       ; comma position
ED_COL      DB 74       ; column position
COL_SCAN    DB 10       ; scan code position
COL_ASCII   DB 15       ; ascii code position

; variables
SCAN_CODE   DB 0        ; scan code
ASCII_CODE  DB 0        ; ascii code
CTRL_FLAGS  DB 0        ; control flag
COL         DB 0        ; column
NUM         DB ?        ; temporary variable
INS_FLAG    DB 0        ; 1: insert mode, 0: overwrite mode

.CODE

CLR_SCR   MACRO ROW         ; clear screen
    MOV AX, COLORBUFFER
    MOV ES, AX              ; segment register for destination
    MOV DI, 0               ; ES:[DI] position for video buffer
    MOV CX, 2000            ; 2000 = 25*80 = window size
    MOV AL, ' '             ; use blank to clear
    MOV AH, NORMAL_ATTRIB   ; normal char attribute
    CLD                     ; in incremental direction
    REP STOSW               ; repeat 2000 times to clear
ENDM

DISP_FUN MACRO              ; dispaly function header 'Edit'
                            ; ES:[DI] destination address
    MOV DI, 0               ; initial offset = 0
    MOV SI, OFFSET FUN      ;
    INC SI                  ; DS:[SI] source address

    MOV CL, FUN             ; #words for 'Edit'
    MOV CH, 0
    CLD                     ; in incremental direction
    REP MOVSW               ; from source to destination
ENDM    

DISP_ROW   MACRO Y          ; display a row of 80 '-' in video buffer
    MOV AX, 160             ; 80 chars per row, 2 bytes per char
    MUL Y                   ; skip #rows
    MOV DI, AX              ; ES:[DI] destination address
    MOV CX, 80              ; 80 chars per row
    MOV AL, '-'             ; char '-'
    MOV AH, NORMAL_ATTRIB   ; normal char attribute
    CLD                     ; in incremental direction
    REP STOSW               ; repeat 80 times
    DISP_STR ED_COMMA, ROW24, COMMA   ; place comma in status row
ENDM

CLR_EDITBUF  MACRO          ; clear edit buffer
    MOV AX, COLORBUFFER
    MOV ES, AX
    MOV DI, EDITSTART
    MOV CX, EDITSIZE
    MOV AL, ' '
    MOV AH, NORMAL_ATTRIB
    CLD                     ; in incremental direction
    REP STOSW
ENDM    

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; memory-type conversion from (X,Y) to video buffer offset DI
; input:  (X,Y)
; output: DI = 2*(80*Y+X) = offset in video buffer
XY2DI_MEM MACRO X, Y        ; convert (X,Y) to DI, offset in video buffer
    MOV AX, 80
    MOV BL, Y
    MUL BL
    MOV BL, X
    MOV BH, 0
    ADD AX, BX
    SHL AX, 1
    MOV DI, AX              ; DI = 2 * (80 * Y + X)
ENDM

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; register-type conversion from (X,Y) to video buffer offset DI
; input:  (X,Y)=(DL,DH)
; output: DI = 2*(80*Y+X) = offset in video buffer
XY2DI_REG MACRO               
    PUSH AX
    PUSH BX

    MOV AX, 80              ; 80
    MOV BL, DH              ; Y
    MUL BL                  ; AX = 80 * Y

    MOV BL, DL              ; X
    MOV BH, 0               ; NOTE: 16-bit to avoid 8-bit overflow
    ADD AX, BX              ; AX = 80 * Y + X

    SHL AX, 1               ; AX = 2 * (80 * Y + X)
    MOV DI, AX              ; DI = 2 * (80 * Y + X)

    POP BX
    POP AX
ENDM

; display string
DISP_STR MACRO X, Y, STR1   ; ES:[DI] destination address
    PUSHA
    XY2DI_MEM X,Y
    MOV SI, OFFSET STR1
    INC SI                  ; DS:[SI] source address
    MOV CL, STR1            ; string length (#words)
    MOV CH, 0
    CLD                     ; in incremental direction
    REP MOVSW               ; from source to destination
    POPA
ENDM

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; check & display INS, CAPSLOCK, NUMLOCK
DISP_CTRLKEYS MACRO         
                            ; INT 16H, 2   (BIOS interrupts)
                            ; AL = bitfield[7:0] = CTRL_FLAGS
                            ; bitfield  7: insert
                            ;           6: caps lock
                            ;           5: num lock
                            ;           4: scroll lock
                            ;           3: alt
                            ;           2: ctrl
                            ;           1: left shift
                            ;           0: right shift
    PUSHA

    MOV AH, 2                           ; read control key status
    INT 16H
    MOV CTRL_FLAGS, AL                  ; control flags

    ; check INS key
    MOV COL, 40
    MOV BL, CTRL_FLAGS
    AND BL, 10000000B                   ; mask out INS status
    .IF BL == 0
        DISP_STR COL, ROW24, BLNK       ; display blank
        MOV INS_FLAG, 0
    .ELSE
        DISP_STR COL, ROW24, INSERT     ; display 'INS'
        MOV INS_FLAG, 1
    .ENDIF

    ; check CAPSLOCK key
    MOV COL, 50
    MOV BL, CTRL_FLAGS
    AND BL, 01000000B                   ; mask out CAPS status
    .IF BL == 0
        DISP_STR COL, ROW24, BLNK       ; display blank
    .ELSE
        DISP_STR COL, ROW24, CAPSLOCK   ; display 'CAPS'
    .ENDIF

    ; check NUMLOCK key
    MOV COL, 60
    MOV BL, CTRL_FLAGS
    AND BL, 00100000B                   ; mask out NUMLOCK status
    .IF BL == 0
        DISP_STR COL, ROW24, BLNK       ; display blank
    .ELSE
        DISP_STR COL, ROW24, NUMLOCK    ; display 'NUMLOCK'
    .ENDIF

    POPA
ENDM

; for use in DEL & BACKSPACE only
APPEND_BLANK MACRO          ; the last char in a line is set to ' '
    PUSH DX                 
    MOV DL, 79
    XY2DI_REG
    MOV AX, 0720H           ; blank (space) with normal attribute
    MOV ES:[DI], AX 
    POP DX
ENDM

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; major routine: 
; display edit result for each key pressed
; at cursor position (X,Y)=(DL,DH)
; convert (X,Y) to DI, offset to video buffer
DISP_EDIT   MACRO
    LOCAL EX

    ;;;;;;;;;;;;;;;;;;;;;;;;;
    ; key with scan code only
    .IF ASCII_CODE == 0                     
        
        .IF SCAN_CODE == UPARROW_KEY
            .IF DH > FIRST_ROW
                DEC DH                      ; Y = Y-1
                SET_CURSOR                  ; set cursor position (X,Y)
            .ENDIF
        .ELSEIF SCAN_CODE == DOWNARROW_KEY
            .IF DH < MAX_ROW
                INC DH                      ; Y = Y+1
                SET_CURSOR                  
            .ENDIF    
        .ELSEIF SCAN_CODE == RIGHTARROW_KEY
            .IF DL < 79    
                INC DL                      ; X = X+1
                SET_CURSOR
            .ENDIF    
        .ELSEIF SCAN_CODE == LEFTARROW_KEY
            .IF DL > 0
                DEC DL                      ; X = X-1
                SET_CURSOR
            .ENDIF    
        .ELSEIF SCAN_CODE == HOME_KEY
            MOV DL, 0                       ; X = 0
            SET_CURSOR
        .ELSEIF SCAN_CODE == END_KEY
            MOV DL, 79                      ; X = 79
            SET_CURSOR

        .ELSEIF SCAN_CODE == DEL_KEY
            .IF DL < 79
                PUSH DS             ; push DS to stack

                MOV BX, ES          ; segment register for video buffer 
                MOV DS, BX          ; DS = ES = 0B800H
                ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                                    ; DS is changed temporarily
                                    ; do not use .data memory in this section

                MOV CL, 79          ; max X index
                SUB CL, DL          ; #trailing chars in the line
                MOV CH, 0           ; CX : #chars to move

                XY2DI_REG           ; (X,Y)=(DL,DH) => DI, destination

                MOV SI, DI          ; source DS:[SI]
                ADD SI, 2           ; 2 bytes per display char in text mode

                CLD                 ; in incremental direction
                REP MOVSW           ; move trailing chars to ES:[DI]
                ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

                POP DS              ; pop DS for .data variables     
                SET_CURSOR          ; NOTE: variables in data segment use DS
            .ENDIF
            APPEND_BLANK            ; empty the last char
        .ENDIF

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; keys with non-null ASCII codes
    .ELSEIF ASCII_CODE == ENTER_KEY
            .IF DH >= MAX_ROW
                JMP EX
            .ENDIF
            INC DH
            MOV DL, 0
            SET_CURSOR
    .ELSEIF ASCII_CODE == TAB_KEY   ; TAB: move 4 positions 
        .IF DL < 75    
            ADD DL, 4
            SET_CURSOR
        .ENDIF
    .ELSEIF ASCII_CODE == BACKSPACE_KEY
        .IF DL > 0
            PUSH DS

            MOV BX, ES          ; segment registers
            MOV DS, BX          ; for video buffer

            ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                                ; DS is changed temporarily
                                ; do not use .data memory in this section
            MOV CL, 80          ; max X index + 1
            SUB CL, DL          ; #trailing chars in the line
            MOV CH, 0           ; CX : #chars to move

            XY2DI_REG          ; (X,Y)=(DL,DH) => DI, destination

            MOV SI, DI          ; source DS:[SI]
            SUB DI, 2           ; 2 bytes per display char in text mode

            CLD                 ; in incremental direction
            REP MOVSW           ; move trailing chars to ES:[DI]
            ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

            POP DS              ; pop DS for .data variables  

            APPEND_BLANK
            DEC DL              ; X = X-1
            SET_CURSOR          ; NOTE: variables in data segment use DS

        .ENDIF  

    ;;;;;;;;;;;;;;;
    ; ordinary keys
    .ELSE
        .IF INS_FLAG == 1                     
            PUSH DS

            MOV BX, ES          ; segment registers
            MOV DS, BX          ; for video buffer

            ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                                ; DS is changed temporarily
                                ; do not use .data memory in this section
            MOV CL, 79          ; max X index
            SUB CL, DL          ; #trailing chars in the line
            MOV CH, 0           ; CX : #chars to move
                        
            PUSH DX             ; push DX to stack  
            MOV DL, 79          ; set X to rightmost column
            XY2DI_REG           ; (X,Y)=(DL,DH) => DI, destination
            POP DX              ; restore DX

            MOV SI, DI          ; source DS:[SI]
            SUB SI, 2           ; 2 bytes per display char in text mode

            STD                 ; in decremental direction
            REP MOVSW           ; move trailing chars to ES:[DI]
            CLD                 ; restore to normal incremental direction
            ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

            POP DS              ; pop DS for .data variables  
        .ENDIF

        XY2DI_REG                 ; DI = offset to video buffer
        MOV AH, NORMAL_ATTRIB
        MOV AL, ASCII_CODE
        MOV ES:[DI], AX

        .IF DL >= 79 
            .IF DH < MAX_ROW
                INC DH              ; Y=Y+1
                MOV DL, 0           ; X=0
            .ENDIF
        .ELSE
            INC DL                  ; X=X+1
        .ENDIF
        SET_CURSOR
    .ENDIF
EX:

ENDM


RESET_CURSOR MACRO      ; reset cursor position
    MOV DL, 0           ; X = 0
    MOV DH, 2           ; Y = 2
    SET_CURSOR
ENDM

SET_CURSOR MACRO        ; set cursor position to (X,Y) = (DL, DH)
    MOV BH, 0           ; page number = 0 for INT 10H, 2
    MOV AH, 02H
    INT 10H

    MOV NUM, DL                     ; X
    ;ADD NUM, 1                     ; [0,79] -> [1,80]
    I2VBUF NUM, ED_COL, ROW24

    MOV NUM, DH                     ; Y
    SUB NUM, 2                      ; [2,21] -> [0,19]
    I2VBUF NUM, ED_ROW, ROW24   
ENDM

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 8-bit integer to 3-digit chars in video buffer
I2VBUF	MACRO I, X, Y
	LOCAL L2, , NEXT, DONE
	PUSHA	

    XY2DI_MEM X, Y                          ; compute DI from (X,Y)
    ADD DI, NDIGIT2                         ; 3 chars = 6 bytes for text mode

	MOV	BL, 10                              ; decimal multiplier 10                                   
    MOV CX, NDIGIT                          ; 3 digits
        
    MOV AL, I                               ; initial integer
    MOV AH, 0
L2:
    DIV BL                                  ; divide by 10, quotient in AL

    .IF AH == 0                             ; if remainder == 0:
        .IF CX != NDIGIT && AL == 0         ; for additional leading zeros,
            MOV DX, 0720H                   ; use blank in place of '0'
            JMP NEXT
        .ENDIF
    .ENDIF

    MOV DL, AH                              ; remainder in AH
    ADD DL, 30H                             ; convert to ASCII
    MOV DH, NORMAL_ATTRIB                   ; 07H

    MOV AH, 0                               ; NOTE: clear AH for next division

NEXT:
    SUB DI, 2                               ; 2 bytes per char in video buffer
    MOV ES:[DI], DX                         ; set a digit in video buffer

    LOOP L2                                 ; check next digit

DONE:
    POPA	 
ENDM


MAIN    PROC    FAR
    MOV AX, @DATA
    MOV DS, AX

    CLR_SCR                     ; clear screen
    DISP_FUN                    ; display 'Edit' 
    DISP_ROW ROW2               ; display ------
    CLR_EDITBUF                 ; clear edit buffer
    DISP_ROW ROW23              ; display ------
    RESET_CURSOR                ; reset cursor position to (0,2)

; main loop
CHECK_KEY:

    DISP_CTRLKEYS   ; check keys without ASCII codes: INS, CAPSLOCK, NUMLOCK

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; check if any key is pressed
    MOV AH, 0BH                 ; check keystroke
    INT 21H                     ; using DOS interrupt: INT 21H, 0BH

    .IF AL != 0                 ; if a char is waiting in keyboard buffer               
        MOV AH, 0               ; find the associated scan code & ASCII code
        INT 16H                 ; using BIOS interrupt: INT 16H, 0
        MOV SCAN_CODE, AH       ; scan code = AH
        MOV ASCII_CODE, AL      ; ASCII code = AL

        ; the following 2 lines are for debug only
        ;I2VBUF SCAN_CODE, COL_SCAN, ROW24     ; display scan code
        ;I2VBUF ASCII_CODE, COL_ASCII, ROW24   ; display ASCII code

        .IF ASCII_CODE == ESC_KEY               ; if ESC, exit text editor
            JMP  RETDOS                         ; return to DOS                         
        .ENDIF

        DISP_EDIT               ; major routine for each key pressed

    .ENDIF

    ; insert delay here if needed
    JMP CHECK_KEY               ; check keyboard again

RETDOS:    
    MOV AH,4CH
    INT 21H                     ; return to DOS
MAIN ENDP

END MAIN