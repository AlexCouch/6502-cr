* = $0200
    ;Store a word of data
    lda #$5
    sta $30 ;0x0030
    lda #$3
    sta $31

    lda #$50
    sta $30
    lda #$08
    sta $31

    lda #$f
    sta ($30), Y
    iny
    lda #$8
    sta ($30), Y

