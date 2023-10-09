; Define memory addresses for various ports and variables
PORTB            = $4000
PORTA            = $4001
DDRB             = $4002
DDRA             = $4003
PCR              = $400c
IFR              = $400d
IER              = $400e

kb_wptr          = $0000
kb_rptr          = $0001
kb_flags         = $0002

RELEASE          = %00000001
SHIFT            = %00000010

ACIA_DATA        = $6000
ACIA_STATUS      = $6001
ACIA_CMD         = $6002
ACIA_CTRL        = $6003

PR_COMMAND       = "PR"
RD_COMMAND       = "RD"
CL_COMMAND       = "CL"
AD_COMMAND       = "AD"
SB_COMMAND       = "SB"
ML_COMMAND       = "ML"
DI_COMMAND       = "DI"
GO_COMMAND       = "GO"
WR_COMMAND       = "WR"
RE_COMMAND       = "RE"
FI_COMMAND       = "FI"
IF_COMMAND       = "IF"
ST_COMMAND       = "ST"
LN_COMMAND       = "LN"
CV_COMMAND       = "CV"
IN_COMMAND       = "IN"

COMMAND_BUFFER_START = $0004
COMMAND_BUFFER_END   = $0122
INIT_RAM_ADDRESS     = $0003

kb_buffer        = $0200    ; 256-byte input buffer $0200-02ff
buffer           = $0300    ; 256-byte display & command buffer.
command_store    = $0400    ; 512-byte section for variable storage
  .org $e000

reset:
  ldx #$ff
  txs

  lda #$01
  sta PCR
  lda #$82
  sta IER
  cli
  lda #$1f
  sta ACIA_CTRL
  lda #$0b
  sta ACIA_CMD

  lda #$00
  sta kb_flags
  sta kb_wptr
  sta kb_rptr

loop:
  sei
  lda kb_rptr
  cmp kb_wptr
  cli
  bne key_pressed
  jmp loop

key_pressed:
  ldx kb_rptr
  lda kb_buffer, x
  cmp #$0a           ; Check if the key is Enter (newline)
  beq enter_pressed
  cmp #$1b           ; Check if the key is Escape
  beq esc_pressed

  jsr check_commands

  inc kb_rptr
  jmp loop

branch_to_column_40:
  jsr column_40
  jmp loop

enter_pressed:
  lda #$0d
  jsr ECHO
  jmp loop

execute_pr:
  lda kb_rptr   ; Load the current read pointer
  clc
  adc #3        ; Move the pointer past the "PR " command (2 characters plus space)
  sta kb_rptr   ; Update the read pointer

  ; Initialize a buffer to store the text to print
  ldx #0        ; Initialize index for the buffer
  lda #0        ; Clear accumulator to ensure null-terminated string

extract_text:
  lda kb_buffer, x  ; Load the character from the buffer
  cmp #13           ; Check for carriage return (CR)
  beq print_text    ; If CR is found, print the text
  cmp #10           ; Check for line feed (LF)
  beq print_text    ; If LF is found, print the text

  ; Store the character in the buffer
  sta buffer, x
  inx
  bne extract_text  ; Continue extracting characters

print_text:
  ; Print the text using the ECHO subroutine
  ldx #0  ; Initialize index for the buffer
  lda buffer, x
  beq to_loop  ; If the buffer is empty, return to the main loop
  jsr ECHO  ; Print the character
  inx
  jmp print_text  ; Continue printing characters

to_loop:
  jmp loop

check_commands:
  lda #kb_rptr
  cmp kb_wptr
  beq to_error   ; No new input
  lda kb_buffer, x

  ; Check for user input commands and extract values
  ldx #0  ; Initialize index for command comparison

check_pr:
  lda PR_COMMAND, x
  cmp kb_buffer, x  ; Compare the first two characters with "PR"
  beq execute_pr     ; If it matches, execute the "PR" command
  inx
  cpx #2
  bne check_cl

check_cl:
  lda CL_COMMAND, x
  cmp kb_buffer, x  ; Compare the first two characters with "CL"
  beq execute_cl     ; If it matches, execute the "CL" command
  inx
  cpx #2
  bne check_ad

check_ad:
  lda AD_COMMAND, x
  cmp kb_buffer, x
  beq execute_ad
  inx
  cpx #2
  bne check_ml

check_ml:
  lda ML_COMMAND, x
  cmp kb_buffer, x
  beq execute_ml
  inx
  cpx #2
  bne to_error

execute_ml:
  pha
  tya
  pha
  ldy #0
  lda kb_buffer+4       ; Load the 3rd character (assuming 0-based indexing)
  sta command_store     ; Store it in a temporary location
  lda kb_buffer+6       ; Load the 4th character
  sta command_store+1

  ; Load the ASCII characters from memory
  lda command_store     ; Load the first ASCII character
  clc           ; Clear the carry flag
  sbc #$30      ; Subtract ASCII '0'
  cmp #$0A      ; Check if the result is greater than or equal to 10
  bcs not_digit_ml ; If it's not a digit, check for hexadecimal letters

ml:
  sta command_store+4, y
  iny
  cpy #2
  bne execute_ad
  clc
  jsr multiply
  jsr ECHO
  pla
  tay
  pla
  jmp loop

not_digit_ml:
  cmp #$07    ; Check if it's in the range 'A' to 'F'
  bcc to_error   ; If it's not in the range, it's an invalid character

  ; It's a hexadecimal letter ('A'-'F')
  sec         ; Set the carry flag for addition
  sbc #$07    ; Subtract the adjustment for 'A'-'F'
  jmp ml

multiply:
  lda #0
  ldx #8
  lsr command_store+6
ml_loop:
  BCC no_add:
  clc
  adc command_store+7
no_add:
  ror
  ror command_store+6
  dex
  bne ml_loop
  sta command_store+7
  rts

to_error:
  jmp error

execute_ad:
  pha
  ldy #0
  lda kb_buffer+4       ; Load the 3rd character (assuming 0-based indexing)
  sta command_store     ; Store it in a temporary location
  lda kb_buffer+6       ; Load the 4th character
  sta command_store+1

  ; Load the ASCII characters from memory
  lda command_store     ; Load the first ASCII character
  clc           ; Clear the carry flag
  sbc #$30      ; Subtract ASCII '0'
  cmp #$0A      ; Check if the result is greater than or equal to 10
  bcs not_digit ; If it's not a digit, check for hexadecimal letters

done:
  sta command_store+4, y
  iny
  cpy #2
  bne execute_ad
  lda command_store+5
  clc
  adc command_store+6
  jsr ECHO
  pla
  jmp loop

not_digit:
  cmp #$07    ; Check if it's in the range 'A' to 'F'
  bcc error   ; If it's not in the range, it's an invalid character

  ; It's a hexadecimal letter ('A'-'F')
  sec         ; Set the carry flag for addition
  sbc #$07    ; Subtract the adjustment for 'A'-'F'
  jmp done

execute_cl:
  lda kb_buffer+3, x
  beq error

  cmp #40
  beq column_40
  cmp #80
  beq column_80
  bcs column_LOTS

column_40:
  pha
  lda #$0d
  jsr ECHO
  iny
  cpy #40
  bcc column_40
  pla
  rts

column_80
  pha
  lda #$0d
  jsr ECHO
  iny
  cpy #80
  bcc column_80
  pla
  rts

column_LOTS:
  pha
  lda #$0d
  jsr ECHO
  iny
  cpy #240
  bcc column_LOTS
  pla
  rts


error:
  pha
  lda #'e'
  jsr ECHO
  lda #'r'
  jsr ECHO
  lda #'r'
  jsr ECHO
  lda #'o'
  jsr ECHO
  lda #'r'
  jsr ECHO
  pla
  jmp loop

; ECHO subroutine to transmit a character
ECHO:
  pha
  sta ACIA_DATA
  ldx #$ff
TXDELAY:
  dex
  bne TXDELAY
  pla
  rts

; Keyboard interrupt handler
keyboard_interrupt:
  pha
  txa
  pha
  lda kb_flags
  and #RELEASE   ; Check if we're releasing a key
  beq read_key   ; Otherwise, read the key

  lda kb_flags
  eor #RELEASE   ; Flip the releasing bit
  sta kb_flags
  lda PORTA      ; Read key value that's being released
  cmp #$12       ; Check if it's the left shift key
  beq shift_up
  cmp #$59       ; Check if it's the right shift key
  beq shift_up
  jmp exit

shift_up:
  lda kb_flags
  eor #SHIFT  ; Flip the shift bit
  sta kb_flags
  jmp exit

read_key:
  lda PORTA
  cmp #$f0        ; Check if releasing a key
  beq key_release ; Set the releasing bit
  cmp #$12        ; Check if it's the left shift key
  beq shift_down
  cmp #$59        ; Check if it's the right shift key
  beq shift_down

  tax
  lda kb_flags
  and #SHIFT
  bne shifted_key

  lda keymap, x   ; Map to character code
  jmp push_key

shifted_key:
  lda keymap_shifted, x   ; Map to character code

push_key:
  ldx kb_wptr
  sta kb_buffer, x
  inc kb_wptr
  jmp exit

shift_down:
  lda kb_flags
  ora #SHIFT
  sta kb_flags
  jmp exit

key_release:
  lda kb_flags
  ora #RELEASE
  sta kb_flags


exit:
  pla
  tax
  pla
  rti

nmi:
  rti

  .org $fd00
keymap:
  .byte "????????????? `?" ; 00-0F
  .byte "?????q1???zsaw2?" ; 10-1F
  .byte "?cxde43?? vftr5?" ; 20-2F
  .byte "?nbhgy6???mju78?" ; 30-3F
  .byte "?,kio09??./l;p-?" ; 40-4F
  .byte "??'?[=????",$0a,"]?\??" ; 50-5F
  .byte "?????????1?47???" ; 60-6F
  .byte "0.2568",$1b,"??+3-*9??" ; 70-7F
  .byte "????????????????" ; 80-8F
  .byte "????????????????" ; 90-9F
  .byte "????????????????" ; A0-AF
  .byte "????????????????" ; B0-BF
  .byte "????????????????" ; C0-CF
  .byte "????????????????" ; D0-DF
  .byte "????????????????" ; E0-EF
  .byte "????????????????" ; F0-FF
keymap_shifted:
  .byte "????????????? ~?" ; 00-0F
  .byte "?????Q!???ZSAW@?" ; 10-1F
  .byte "?CXDE#$?? VFTR%?" ; 20-2F
  .byte "?NBHGY^???MJU&*?" ; 30-3F
  .byte "?<KIO)(??>?L:P_?" ; 40-4F
  .byte '??"?{+?????}?|??' ; 50-5F
  .byte "?????????1?47???" ; 60-6F
  .byte "0.2568???+3-*9??" ; 70-7F
  .byte "????????????????" ; 80-8F
  .byte "????????????????" ; 90-9F
  .byte "????????????????" ; A0-AF
  .byte "????????????????" ; B0-BF
  .byte "????????????????" ; C0-CF
  .byte "????????????????" ; D0-DF
  .byte "????????????????" ; E0-EF
  .byte "????????????????" ; F0-FF

; Reset/IRQ vectors
  .org $fffa
  .word nmi
  .word reset
  .word keyboard_interrupt
