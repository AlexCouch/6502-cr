* = $0200
    ;Store a word of data
    lda #$5
    sta $30 ;0x0030
    lda #$3
    sta $31

    ;Move a word of data
    lda $30
    sta $0850
    lda $31
    sta $0851

