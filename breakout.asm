; =============================================================================
; Attari Breakout
; Language: NASM x86 Assembly
; AUTHOR: 24F - 0622, ALI AMIR
; =============================================================================

org 100h                       ; .COM program: code/data loaded at offset 100h

section .data
    ; --- Visuals ---
    paddle_char     db  220
    ball_char       db  2           ; hollow smiley glyph in CP437 (not a solid block)
    brick_char      db  178

    ; --- Color Variables (also used to decode which brick color got hit) ---
    col_yellow      db  0x0E
    col_red         db  0x04
    col_green       db  0x02
    col_blue        db  0x01

    ; --- Colors ---
    color_paddle    db  0x09        ; Blue on Black bg
    color_ball      db  0x04        ; Red on Black bg

    ; --- Positions ---
    paddle_x        dw  35
    paddle_y        dw  23
    paddle_width    dw  10           ; reverted to the original width - see check_paddle_hit

    ball_x          dw  40
    ball_y          dw  20
    ball_dx         dw  1
    ball_dy         dw  -1

    screen_width    dw  80
    screen_height   dw  25

    ; --- Game State ---
    score           dw  0
    lives           dw  3
    brick_count     dw  0           ; counts LOGICAL bricks left (not individual characters)
    current_level   dw  1
    level_shown     dw  0           
    straight_streak dw  0          
    hit_color       db  0          
    delay_value     dw  02500h

    ; --- Welcome screen text (null-terminated, printed in color via print_attr_str) ---
    txt_title       db  'A T A R I   B R E A K O U T', 0
    txt_subtitle    db  '3 Levels of Brick-Smashing Action!', 0
    txt_controls    db  'Controls: <- / -> Arrow Keys to Move the Paddle', 0
    txt_objective   db  'Objective: Smash every brick before you run out of lives!', 0
    txt_angle_tip   db  'Tip: WHERE you hit the paddle sets the bounce angle!', 0
    txt_leg_yellow  db  'Yellow Bricks = 10 pts  (High Pitch)', 0
    txt_leg_red     db  'Red Bricks    = 20 pts  (Medium Pitch)', 0
    txt_leg_green   db  'Green Bricks  = 30 pts  (Low Pitch)', 0
    txt_leg_blue    db  'Blue Bricks   = 40 pts  (Bass Pitch)', 0
    txt_prompt      db  '>>> Press ENTER to Start Smashing! <<<', 0
    txt_exit        db  'Press E to Exit', 0

    ; --- Level-complete screen text ---
    txt_lvl_1       db  'LEVEL ', 0
    txt_lvl_2       db  ' COMPLETE!', 0
    txt_lvl_motiv1  db  'Awesome reflexes - every brick stood no chance!', 0
    txt_lvl_motiv2  db  'Lives refilled to 3 - good luck out there!', 0
    txt_lvl_prompt  db  'Press ENTER to Continue   |   Press E to Exit', 0

    ; --- End-state / restart messages (unchanged) ---
    msg_gameover    db  'GAME OVER! Final Score: $'
    msg_win         db  'VICTORY! All Levels Cleared! Score: $'
    msg_restart     db  'Press R to Restart or E to Exit$'
    msg_score       db  'Score: $'
    msg_lives       db  'Lives: $'
    msg_lvl_txt     db  'Lvl: $'

section .text
    global _start

_start:
    mov ax, 0003h       ; set 80x25 16-color text video mode
    int 10h
    mov ah, 01h         ; hide the blinking text cursor
    mov ch, 20h
    int 10h

show_welcome:
    mov bl, 0x1F                    ; bright white on blue - intro theme
    call clear_screen_colored

    ; --- decorative double-line border around the title ---
    mov dh, 2
    mov dl, 18
    mov cx, 44
    mov al, 205                     ; horizontal double-line char
    mov bl, 0x1E                    ; bright yellow on blue
    call draw_hline
    mov dh, 2
    mov dl, 18
    mov al, 201                     ; top-left corner
    call draw_char_at
    mov dh, 2
    mov dl, 61
    mov al, 187                     ; top-right corner
    call draw_char_at

    mov dh, 6
    mov dl, 18
    mov cx, 44
    mov al, 205
    mov bl, 0x1E
    call draw_hline
    mov dh, 6
    mov dl, 18
    mov al, 200                     ; bottom-left corner
    call draw_char_at
    mov dh, 6
    mov dl, 61
    mov al, 188                     ; bottom-right corner
    call draw_char_at

    ; --- title + subtitle inside the border ---
    mov dh, 3
    mov dl, 27
    mov bl, 0x1E
    mov si, txt_title
    call print_attr_str

    mov dh, 4
    mov dl, 22
    mov bl, 0x1F
    mov si, txt_subtitle
    call print_attr_str

    ; --- controls / objective ---
    mov dh, 8
    mov dl, 18
    mov bl, 0x1F
    mov si, txt_controls
    call print_attr_str

    mov dh, 9
    mov dl, 18
    mov si, txt_objective
    call print_attr_str

    mov dh, 10
    mov dl, 18
    mov bl, 0x1E                    ; bright yellow on blue - make the tip stand out
    mov si, txt_angle_tip
    call print_attr_str

    ; --- scoring legend, colored with the EXACT attribute each brick uses in-game ---
    mov dh, 12
    mov dl, 18
    mov bl, [col_yellow]
    mov si, txt_leg_yellow
    call print_attr_str

    mov dh, 13
    mov dl, 18
    mov bl, [col_red]
    mov si, txt_leg_red
    call print_attr_str

    mov dh, 14
    mov dl, 18
    mov bl, [col_green]
    mov si, txt_leg_green
    call print_attr_str

    mov dh, 15
    mov dl, 18
    mov bl, [col_blue]
    mov si, txt_leg_blue
    call print_attr_str

    ; --- blinking call-to-action ---
    mov dh, 18
    mov dl, 20
    mov bl, 0x9F                    ; blink + bright white, blue bg
    mov si, txt_prompt
    call print_attr_str

    mov dh, 19
    mov dl, 32
    mov bl, 0x1F
    mov si, txt_exit
    call print_attr_str

wait_start:
    mov ah, 00h         ; blocking key read
    int 16h
    cmp al, 13          ; Enter -> start game
    je full_reset_game
    cmp al, 'e'
    je exit_program_jmp
    cmp al, 'E'
    je exit_program_jmp
    jmp wait_start

exit_program_jmp:
    jmp exit_program

; =============================================================================
; INITIALIZATION
; =============================================================================

full_reset_game:
    ; brand new game: wipe score and go back to level 1
    mov word [score], 0
    mov word [current_level], 1
    jmp init_level_settings

init_level_settings:
    ; runs at game start AND after every level clear: refill lives, pick speed
    mov word [lives], 3

    cmp word [current_level], 1
    je set_spd_1
    cmp word [current_level], 2
    je set_spd_2
    mov word [delay_value], 01000h ; level 3+ : Fast
    jmp init_round

set_spd_1:
    mov word [delay_value], 03000h ; level 1: Slow
    jmp init_round
set_spd_2:
    mov word [delay_value], 02000h ; level 2: Medium
    jmp init_round

init_round:
    ; reset ball/paddle to starting spots and draw the current level's bricks
    mov word [paddle_x], 35
    mov word [ball_x], 40
    mov word [ball_y], 20
    mov word [ball_dx], 1
    mov word [ball_dy], -1
    mov word [brick_count], 0

    call clear_screen
    call draw_bricks_logic
    call draw_ui
    call draw_paddle
    call draw_ball

    mov cx, 15
    call delay_custom   ; brief pause so player can see the level before it moves

game_loop:
    mov ah, 01h         ; any key waiting? (non-blocking check)
    int 16h
    jz no_input

    mov ah, 00h         ; consume that key
    int 16h

    cmp al, 'e'
    je exit_program_jmp
    cmp al, 'E'
    je exit_program_jmp

    cmp ah, 4Bh         ; left arrow scancode
    je move_left
    cmp ah, 4Dh         ; right arrow scancode
    je move_right
    jmp no_input

move_left:
    call move_paddle_left
    jmp no_input
move_right:
    call move_paddle_right

no_input:
    ; one full frame: pace it, erase old ball, move+collide, redraw, check end conditions
    call delay_frame
    call clear_old_ball
    call update_ball_pos

    call draw_ball
    call draw_ui

    cmp word [lives], 0
    je jmp_gameover

    cmp word [brick_count], 0
    je level_cleared

    jmp game_loop

jmp_gameover:
    jmp state_gameover
jmp_win:
    jmp state_win

; =============================================================================
; LEVEL LOGIC & EVENTS
; =============================================================================

level_cleared:
    ; remember which level we just finished, for the congrats screen
    mov ax, [current_level]
    mov [level_shown], ax

    inc word [current_level]
    cmp word [current_level], 4
    je jmp_win

    ; triumphant two-note rising jingle
    mov bx, 2000
    call sound_generic
    mov bx, 1000
    call sound_generic

    mov bl, 0x02                    ; dark green on black - moodier "success" screen
    call clear_screen_colored

    ; "LEVEL <n> COMPLETE!" with the digit spliced between two text fragments
    mov dh, 8
    mov dl, 28
    mov bl, 0x0A                    ; bright green accent on black, for the headline
    mov si, txt_lvl_1
    call print_attr_str
    mov ax, [level_shown]
    add al, '0'
    call draw_char_at               ; dh/dl/bl are still correct from print_attr_str above
    inc dl
    mov si, txt_lvl_2
    call print_attr_str

    ; motivational lines - plain dark green, matching the screen's base tone
    mov dh, 11
    mov dl, 15
    mov bl, 0x02
    mov si, txt_lvl_motiv1
    call print_attr_str

    mov dh, 12
    mov dl, 15
    mov si, txt_lvl_motiv2
    call print_attr_str

    ; running score (plain DOS print - inherits the dark green fill automatically)
    mov dh, 14
    mov dl, 30
    call set_cursor
    mov dx, msg_score
    mov ah, 09h
    int 21h
    mov ax, [score]
    call print_num

    ; prompt
    mov dh, 17
    mov dl, 16
    mov bl, 0x8A                    ; blink + bright green on black
    mov si, txt_lvl_prompt
    call print_attr_str

level_wait:
    mov ah, 00h
    int 16h
    cmp al, 13                      ; Enter -> go to the next level
    je init_level_settings
    cmp al, 'e'
    je exit_program_jmp
    cmp al, 'E'
    je exit_program_jmp
    jmp level_wait

; =============================================================================
; LOGIC: SCORING
; =============================================================================

check_brick_hit:
    ; is there a brick exactly where the ball currently is?
    mov dh, byte [ball_y]
    mov dl, byte [ball_x]
    call read_char_at

    cmp al, [brick_char]
    jne no_brick

    dec word [brick_count]     ; one logical brick is about to be cleared
    and ah, 0x0F                ; keep only the foreground-color bits of the attribute
    mov [hit_color], ah         ; remember it - sound_generic below will clobber AX

    mov bl, [col_yellow]
    cmp ah, bl
    je score_yellow

    mov bl, [col_red]
    cmp ah, bl
    je score_red

    mov bl, [col_green]
    cmp ah, bl
    je score_green

    jmp score_blue

; Note on Sound Values:
; Lower Value = Higher Pitch
; Higher Value = Lower Pitch

score_yellow:
    add word [score], 10
    mov bx, 1200        ; High Pitch (Small divisor)
    call sound_generic
    jmp finish_hit

score_red:
    add word [score], 20
    mov bx, 2000        ; Medium Pitch
    call sound_generic
    jmp finish_hit

score_green:
    add word [score], 30
    mov bx, 3500        ; Low Pitch
    call sound_generic
    jmp finish_hit

score_blue:
    add word [score], 40
    mov bx, 6000        ; Bass Pitch (Large divisor)
    call sound_generic
    jmp finish_hit

finish_hit:
    call remove_brick_cluster   ; wipe the whole same-colored run, not just one cell
    neg word [ball_dy]          ; bounce the ball vertically
no_brick:
    ret

; =============================================================================
; PHYSICS & MOVEMENT
; =============================================================================

clear_old_ball:
    ; erase the ball from its PREVIOUS position before it moves this frame
    mov dh, byte [ball_y]
    mov dl, byte [ball_x]
    mov bl, 0
    mov al, ' '
    call draw_char_at
    ret

update_ball_pos:
    ; horizontal movement - speed can now be -2..+2 (see check_paddle_hit for why)
    mov ax, [ball_x]
    add ax, [ball_dx]
    mov [ball_x], ax

    cmp word [ball_x], 0
    jl bounce_x_right        ; went past the left edge
    mov ax, [screen_width]
    dec ax
    cmp [ball_x], ax
    jg bounce_x_left          ; went past the right edge
    jmp check_y

bounce_x_right:
    mov word [ball_x], 0          ; snap back onto the screen
    neg word [ball_dx]            ; reverse direction but KEEP the angle magnitude
    ret
bounce_x_left:
    mov ax, [screen_width]
    dec ax
    mov [ball_x], ax              ; snap back onto the screen (col 79)
    neg word [ball_dx]
    ret

check_y:
    ; move vertically, then figure out what the ball just ran into
    mov ax, [ball_y]
    add ax, [ball_dy]
    mov [ball_y], ax

    cmp word [ball_y], 1
    jle bounce_y_down        ; hit the top wall (row 0/1, kept clear for UI)

    mov bx, [paddle_y]
    dec bx
    cmp [ball_y], bx
    je check_paddle_hit      ; one row above the paddle -> test for a hit

    mov bx, [paddle_y]
    cmp [ball_y], bx
    jge check_death            ; triggers right at the paddle's row on a miss, not one frame late

    call check_brick_hit      ; anywhere else -> might be a brick
    ret

bounce_y_down:
    mov word [ball_dy], 1
    ret

check_paddle_hit:
    ; is the ball's X inside the paddle's actual width?
    mov ax, [ball_x]
    cmp ax, [paddle_x]
    jl no_hit
    mov bx, [paddle_x]
    add bx, [paddle_width]
    cmp ax, bx
    jge no_hit                ; paddle only covers width-1 past paddle_x

    sub ax, [paddle_x]        ; ax = where across the paddle we got hit (0..9)

    cmp ax, 2
    jl pb_sharp_left
    cmp ax, 4
    jl pb_soft_left
    cmp ax, 6
    jl pb_center
    cmp ax, 8
    jl pb_soft_right
    mov word [straight_streak], 0   ; any non-center hit resets the anti-lock counter
    mov word [ball_dx], 2      ; far-right edge -> ~27 degrees, sharp/shallow right
    jmp pb_bounce
pb_sharp_left:
    mov word [straight_streak], 0
    mov word [ball_dx], -2     ; far-left edge -> ~27 degrees, sharp/shallow left
    jmp pb_bounce
pb_soft_left:
    mov word [straight_streak], 0
    mov word [ball_dx], -1     ; left-of-center -> 45 degrees, gentle angle left
    jmp pb_bounce
pb_center:

    inc word [straight_streak]
    cmp word [straight_streak], 3
    jl pb_center_straight
    mov word [straight_streak], 0
    mov ax, [ball_x]                ; cheap coin-flip: which way to nudge
    test ax, 1
    jz pb_center_nudge_left
    mov word [ball_dx], 1
    jmp pb_bounce
pb_center_nudge_left:
    mov word [ball_dx], -1
    jmp pb_bounce
pb_center_straight:
    mov word [ball_dx], 0      ; dead center -> 90 degrees, straight up
    jmp pb_bounce
pb_soft_right:
    mov word [straight_streak], 0
    mov word [ball_dx], 1      ; right-of-center -> 45 degrees, gentle angle right

pb_bounce:
    mov bx, 900
    call sound_generic          ; paddle bounce sound
    mov word [ball_dy], -1
no_hit:
    ret

check_death:
    ; ball passed the paddle's row without bouncing -> lose a life and respawn
    mov ax, [screen_height]
    dec ax
    cmp [ball_y], ax
    jl ret_phys

    mov bx, 9000
    call sound_generic          ; low "death" tone
    dec word [lives]
    mov word [ball_x], 40
    mov word [ball_y], 20
    mov word [ball_dx], 1
    mov word [ball_dy], -1
    mov word [straight_streak], 0
ret_phys:
    ret

remove_brick_cluster:
    ; erase every cell left AND right of the hit point that is the SAME character AND
    ; the SAME color as what got hit.
    push dx
    push cx
    mov cl, dl
scan_l:
    mov dl, cl
    call read_char_at           ; AL = char, AH = attribute
    cmp al, [brick_char]
    jne start_erase
    and ah, 0x0F
    cmp ah, [hit_color]
    jne start_erase             ; different-colored neighbor brick - stop, don't eat it
    cmp cl, 0
    je begin_erase             
    dec cl
    jmp scan_l
start_erase:
    inc cl
begin_erase:
erase_lp:
    mov ax, [screen_width]
    dec ax
    cmp cl, al
    jg erase_end                 
    mov dl, cl
    call read_char_at
    cmp al, [brick_char]
    jne erase_end
    and ah, 0x0F
    cmp ah, [hit_color]
    jne erase_end                ; different-colored neighbor brick - stop here too
    mov bl, 0
    mov al, ' '
    call draw_char_at
    inc cl
    jmp erase_lp
erase_end:
    pop cx
    pop dx
    ret

; =============================================================================
; DRAWING
; =============================================================================

draw_bricks_logic:
    ; pick the brick layout for whichever level we're on
    cmp word [current_level], 1
    je draw_level_1
    cmp word [current_level], 2
    je draw_level_2
    jmp draw_level_3

; --- LEVEL 1: RAINBOW ROW - the 6-brick layout
draw_level_1:
    mov dh, 4
    mov dl, 15

    mov bl, [col_yellow]
    call draw_one_brick
    inc word [brick_count]
    add dl, 2

    mov bl, [col_red]
    call draw_one_brick
    inc word [brick_count]
    add dl, 2

    mov bl, [col_green]
    call draw_one_brick
    inc word [brick_count]
    add dl, 2

    mov bl, [col_blue]
    call draw_one_brick
    inc word [brick_count]
    add dl, 2

    mov bl, [col_red]
    call draw_one_brick
    inc word [brick_count]
    add dl, 2

    mov bl, [col_yellow]
    call draw_one_brick
    inc word [brick_count]
    add dl, 2
    ret

; --- LEVEL 2: the split-row layout
draw_level_2:
    mov dh, 3
    mov dl, 4
    mov cx, 4
    mov bl, [col_yellow]
l2_y: push cx
    call draw_one_brick
    inc word [brick_count]
    add dl, 2
    pop cx
    loop l2_y

    mov cx, 4                 ; was 5 in the original - that overflowed past col 79
    mov bl, [col_red]
l2_r: push cx
    call draw_one_brick
    inc word [brick_count]
    add dl, 2
    pop cx
    loop l2_r

    mov dh, 5
    mov dl, 8
    mov cx, 4
    mov bl, [col_green]
l2_g: push cx
    call draw_one_brick
    inc word [brick_count]
    add dl, 2
    pop cx
    loop l2_g

    mov cx, 4
    mov bl, [col_blue]
l2_b: push cx
    call draw_one_brick
    inc word [brick_count]
    add dl, 2
    pop cx
    loop l2_b
    ret

; --- LEVEL 3: FULL GRID - 4 full-width rows, ZERO gap, 11 bricks each.
draw_level_3:
    mov dh, 3
    mov dl, 1
    mov bh, 0            ; row 1 cycle starts on yellow
    call draw_rainbow_row

    mov dh, 5
    mov dl, 1
    mov bh, 1            ; row 2 cycle starts on red
    call draw_rainbow_row

    mov dh, 7
    mov dl, 1
    mov bh, 2            ; row 3 cycle starts on green
    call draw_rainbow_row

    mov dh, 9
    mov dl, 1
    mov bh, 3            ; row 4 cycle starts on blue
    call draw_rainbow_row
    ret

draw_rainbow_row:
    ; draws 11 zero-gap bricks across row DH, col DL, cycling colors so every brick
    ; differs from its neighbor. BH = starting color index (0=yellow,1=red,2=green,
    ; 3=blue), set by the caller before calling.
    push cx
    mov cx, 11
drr_lp:
    push cx
    cmp bh, 0
    je drr_yellow
    cmp bh, 1
    je drr_red
    cmp bh, 2
    je drr_green
    mov bl, [col_blue]
    jmp drr_draw
drr_yellow:
    mov bl, [col_yellow]
    jmp drr_draw
drr_red:
    mov bl, [col_red]
    jmp drr_draw
drr_green:
    mov bl, [col_green]
drr_draw:
    call draw_one_brick
    inc word [brick_count]
    inc bh
    cmp bh, 4
    jl drr_ok
    mov bh, 0
drr_ok:
    pop cx
    loop drr_lp
    pop cx
    ret

draw_one_brick:
    ; draws one 7-cell-wide brick of color BL starting at row DH, col DL
    push cx
    mov cx, 7
    d_pixel:
        mov al, [brick_char]
        call draw_char_at
        inc dl
        loop d_pixel
    pop cx
    ret

move_paddle_left:
    ; slide paddle left by 4, clamped to column 0
    cmp word [paddle_x], 0
    jle ret_move_l
    call clear_paddle
    sub word [paddle_x], 4
    cmp word [paddle_x], 0
    jge dp_l
    mov word [paddle_x], 0
dp_l: call draw_paddle
ret_move_l:
    ret

move_paddle_right:
    ; slide paddle right by 4, clamped so it never goes past the screen edge
    mov ax, [paddle_x]
    add ax, [paddle_width]
    cmp ax, [screen_width]
    jge ret_move
    call clear_paddle
    add word [paddle_x], 4
    mov ax, [paddle_x]
    add ax, [paddle_width]
    cmp ax, [screen_width]
    jle dp_r
    mov ax, [screen_width]
    sub ax, [paddle_width]
    mov [paddle_x], ax
dp_r: call draw_paddle
ret_move: ret

draw_paddle:
    mov dh, byte [paddle_y]
    mov dl, byte [paddle_x]
    mov cx, [paddle_width]
    mov bl, [color_paddle]
    mov al, [paddle_char]
dp_lp: call draw_char_at
    inc dl
    loop dp_lp
    ret

clear_paddle:
    mov dh, byte [paddle_y]
    mov dl, byte [paddle_x]
    mov cx, [paddle_width]
    mov bl, 0
    mov al, ' '
cp_lp: call draw_char_at
    inc dl
    loop cp_lp
    ret

draw_ball:
    mov dh, byte [ball_y]
    mov dl, byte [ball_x]
    mov bl, [color_ball]
    mov al, [ball_char]
    call draw_char_at
    ret

draw_ui:
    ; redraw the score / lives / level strip along the top row
    mov dh, 0
    mov dl, 2
    call set_cursor
    mov dx, msg_score
    mov ah, 09h
    int 21h
    mov ax, [score]
    call print_num              ; multi-digit safe

    mov dh, 0
    mov dl, 65
    call set_cursor
    mov dx, msg_lives
    mov ah, 09h
    int 21h
    mov ax, [lives]
    add al, '0'                 ; single-digit only (fine: max is 3)
    mov ah, 0Eh
    int 10h

    mov dh, 0
    mov dl, 35
    call set_cursor
    mov dx, msg_lvl_txt
    mov ah, 09h
    int 21h
    mov ax, [current_level]
    add al, '0'                 ; single-digit only (fine: max is 4)
    mov ah, 0Eh
    int 10h
    ret

; =============================================================================
; SOUND SYSTEM
; =============================================================================

sound_generic:
    ; plays a square-wave tone on the PC speaker; BX = pitch divisor (lower = higher pitch)
    mov al, 182
    out 43h, al
    mov ax, bx
    out 42h, al
    mov al, ah
    out 42h, al
    in al, 61h
    or al, 03h
    out 61h, al

    mov cx, 2                   ; shortened from 5: long blocking tones were the main
hold_sound:                    
    push cx                    
    mov cx, 0FFFFh
burn_cycles:
    loop burn_cycles
    pop cx
    loop hold_sound

    in al, 61h
    and al, 0FCh                ; speaker off
    out 61h, al
    ret

; =============================================================================
; HELPERS & END STATES
; =============================================================================

delay_frame:
    ; frame pacing delay, length controlled by [delay_value] (set per level)
    mov cx, [delay_value]
d_out: push cx
    mov cx, 50
d_in: loop d_in
    pop cx
    loop d_out
    ret

delay_custom:
    ; generic busy-wait, outer count passed in CX by the caller
    d_c_out: push cx
    mov cx, 0FFFFh
    d_c_in: loop d_c_in
    pop cx
    loop d_c_out
    ret

set_cursor:
    ; moves the text cursor to row DH, column DL
    mov ah, 02h
    mov bh, 00h
    int 10h
    ret

draw_char_at:
    ; writes char AL with color BL at row DH, col DL (registers preserved for caller)
    push ax
    push bx
    push cx
    push dx
    call set_cursor
    mov ah, 09h
    mov bh, 00h
    mov cx, 1
    int 10h
    pop dx
    pop cx
    pop bx
    pop ax
    ret

read_char_at:
    ; reads back char into AL and color attribute into AH from row DH, col DL
    call set_cursor
    mov ah, 08h
    mov bh, 00h
    int 10h
    ret

print_attr_str:
    ; prints the zero-terminated string at DS:SI in color BL, starting at row DH, col DL
pas_lp:
    lodsb
    cmp al, 0
    je pas_done
    call draw_char_at
    inc dl
    jmp pas_lp
pas_done:
    ret

draw_hline:
    ; draws CX copies of char AL in color BL across row DH starting at col DL (decorative only)
hl_lp:
    call draw_char_at
    inc dl
    loop hl_lp
    ret

clear_screen:
    mov ah, 06h
    mov al, 0
    mov bh, 07h
    mov cx, 0
    mov dh, 24
    mov dl, 79
    int 10h
    ret

clear_screen_colored:
    ; fills the whole screen with attribute BL instead of the plain white-on-black default
    push bx
    mov ah, 06h
    mov al, 0
    mov bh, bl
    mov cx, 0
    mov dh, 24
    mov dl, 79
    int 10h
    pop bx
    ret

print_num:
    ; prints AX as a decimal number (any size, handles 0 correctly)
    push ax
    push bx
    push cx
    push dx
    mov cx, 0
    mov bx, 10
pn_div:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz pn_div
pn_out:
    pop ax
    add al, '0'
    mov ah, 0Eh
    int 10h
    loop pn_out
    pop dx
    pop cx
    pop bx
    pop ax
    ret

state_gameover:
    mov bx, 9000    ; Sad sound
    call sound_generic
    mov bl, 0x04                    ; dark red/maroon on black - somber "game over" mood
    call clear_screen_colored        
    mov dh, 10
    mov dl, 25
    call set_cursor
    mov dx, msg_gameover
    mov ah, 09h
    int 21h
    mov ax, [score]
    call print_num
    jmp show_restart

state_win:
    mov bx, 1000    ; Happy sound
    call sound_generic
    call clear_screen
    mov dh, 10
    mov dl, 20
    call set_cursor
    mov dx, msg_win
    mov ah, 09h
    int 21h
    mov ax, [score]
    call print_num

show_restart:
    mov dh, 12
    mov dl, 22
    call set_cursor
    mov dx, msg_restart
    mov ah, 09h
    int 21h

wait_restart:
    mov ah, 00h
    int 16h
    cmp al, 'r'
    je jump_reset
    cmp al, 'R'
    je jump_reset
    cmp al, 'e'
    je exit_program_jmp_final
    cmp al, 'E'
    je exit_program_jmp_final
    jmp wait_restart

exit_program_jmp_final:
    jmp exit_program

jump_reset:
    jmp full_reset_game

exit_program:
    mov ax, 0003h    ; reset video mode back to normal before returning to DOS
    int 10h
    mov ax, 4C00h    ; DOS terminate
    int 21h