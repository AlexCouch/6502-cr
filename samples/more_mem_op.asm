;This should not be used in emulator until we start doing branching instructions
;This is here for when we do branching later on, first we must complete the arithmetic
;instructions milestone
;-alex

* = $0200
    ldy #1 ;Start iterating array from 0

loop:
    lda array, Y    ;Load the current y index of the array of bytes (see array label at bottom of file)
    sta $30, Y      ;Store the A register into 0x0030 indexed to Y (0x0030, 0x0031, etc)
    iny             ;Increment Y
    cpy #3          ;Compare Y to 3
    bmi loop        ;Branch to loop if Y < 3
    
array: .byte $0, $1, $2, $3


