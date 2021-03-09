* = $0200
    ;Store a word of data
    lda #$5
    sta $30 ;0x0030
    lda #$3
    sta $31

    ;Move a word of data
    ldx #0
    
    lda $30
    sta $0850, X
    inx
    lda $31
    sta $0850, X

    lda $50
    sta $30
    lda $08
    sta $31

    lda #$f
    sta ($30), Y

