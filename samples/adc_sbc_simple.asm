* = $0200
    CLC             ;Ensure carry is clear
    LDA #$5       ;Add the two least significant bytes
    ADC #$3
    STA $30       ;... and store the result
    LDA #$6       ;Add the two most significant bytes
    ADC #$9       ;... and any propagated carry bit
    STA $31       ;... and store the result