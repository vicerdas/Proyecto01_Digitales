.data
LED_MATRIX_BASE:   .word 0xf0000000
LED_MATRIX_WIDTH:  .word 35
LED_MATRIX_HEIGHT: .word 25
COLOR_GREEN:       .word 0x00FF00
COLOR_BLACK:       .word 0x000000
COLOR_RED:         .word 0xFF0000 

#---------------------------------
# Variables del Snake
#---------------------------------
snake_len:         .word 1           # longitud inicial
dir:               .word 3           # 0=arriba,1=abajo,2=izq,3=der
apple_x:           .word 10
apple_y:           .word 10
rand_counter:      .word 0xABCDE     # ya casi no se usa, pero lo dejamos

# Flag: 1 si se comió manzana en este frame
ate_flag:          .word 0

# Para recordar la cola vieja
old_tail_x:        .word 0
old_tail_y:        .word 0

# Tabla de posiciones "pseudoaleatorias" para la manzana
apple_pos_x_table: .word 2, 30, 5, 20, 10, 25, 8, 33, 16, 4
apple_pos_y_table: .word 2,  5,15,  8, 20, 12,22,  3,18,10
apple_pos_idx:     .word 0

# Espacios para el cuerpo (~200 segmentos)
snake_x:   .zero 800
snake_y:   .zero 800

.text
.globl _start

_start:
    # base de la matriz -> a0
    la t0, LED_MATRIX_BASE
    lw a0, 0(t0)

    # width -> a1
    la t0, LED_MATRIX_WIDTH
    lw a1, 0(t0)

    # height -> a2
    la t0, LED_MATRIX_HEIGHT
    lw a2, 0(t0)

    # cabeza inicial
    li s0, 17           # x
    li s1, 12           # y

    la t0, snake_x
    sw s0, 0(t0)
    la t1, snake_y
    sw s1, 0(t1)

    # dirección inicial en s2 y en memoria
    li s2, 3            # derecha
    la t0, dir
    sw s2, 0(t0)

    # idx inicial de la tabla de manzanas
    la t0, apple_pos_idx
    sw x0, 0(t0)

    # semilla rand (no crítico)
    la t0, rand_counter
    li t2, 0x12345
    sw t2, 0(t0)

    # primera manzana
    jal respawn_apple
    jal draw_apple

    # dibujar cabeza
    jal draw_current_led

    j main_loop
    
#---------------------------------
# BUCLE PRINCIPAL
#---------------------------------
main_loop:
    # ate_flag = 0 al inicio del frame
    la t0, ate_flag
    sw x0, 0(t0)

    jal read_input          # D-Pad -> s2
    jal move_snake          # mover cabeza según s2
    jal check_bounds        # si sale de la matriz -> game_over
    jal get_old_tail        # guardar cola vieja
    jal check_apple         # comer manzana / crecer / respawn
    jal update_snake_position   # cuerpo sigue a la cabeza
    jal erase_tail_if_needed    # borra cola vieja si NO comió
    jal draw_snake
    jal draw_apple
    jal game_delay          # controlar velocidad
    j main_loop

#---------------------------------
# DIBUJO CABEZA (verde)
#---------------------------------
draw_current_led:
    mul  t2, s1, a1
    add  t2, t2, s0
    slli t2, t2, 2
    add  t3, a0, t2
    lw   t4, COLOR_GREEN
    sw   t4, 0(t3)
    jr ra

#---------------------------------
# DIBUJO SNAKE COMPLETO
#---------------------------------
draw_snake:
    la t0, snake_len
    lw t1, 0(t0)          # t1 = snake_len

    li t2, 0              # i = 0

draw_snake_loop:
    bge t2, t1, draw_snake_end

    slli t3, t2, 2        # offset = i * 4

    # snake_x[i]
    la t4, snake_x
    add t4, t4, t3
    lw t5, 0(t4)          # x

    # snake_y[i]
    la t4, snake_y
    add t4, t4, t3
    lw t6, 0(t4)          # y

    # dirección del LED = (y*width + x)*4 + base
    mul t0, t6, a1
    add t0, t0, t5
    slli t0, t0, 2
    add t0, a0, t0

    lw t4, COLOR_GREEN
    sw t4, 0(t0)

    addi t2, t2, 1
    j draw_snake_loop

draw_snake_end:
    jr ra

#---------------------------------
# DIBUJO MANZANA (roja)
#---------------------------------
draw_apple:
    la   t0, apple_x
    lw   t1, 0(t0)         # x
    la   t0, apple_y
    lw   t2, 0(t0)         # y

    mul  t3, t2, a1        # y*width
    add  t3, t3, t1        # + x
    slli t3, t3, 2
    add  t4, a0, t3

    lw   t5, COLOR_RED
    sw   t5, 0(t4)
    jr   ra

#---------------------------------
# RESPawn DE MANZANA (usa tabla de posiciones)
#---------------------------------
respawn_apple:
    # t0 = &apple_pos_idx
    la   t0, apple_pos_idx

    # idx_actual
    lw   t1, 0(t0)          # t1 = idx_actual

    # startIdx = idx_actual % 10
    li   t2, 10
    remu t3, t1, t2         # t3 = startIdx

    # avanzar índice global para próxima vez
    addi t1, t1, 1
    sw   t1, 0(t0)

    li   t4, 0              # triedCount = 0

outer_loop:
    bge  t4, t2, fallback   # si ya probamos 10, usar fallback

    # idx = (startIdx + triedCount) % 10
    add  t5, t3, t4
    remu t5, t5, t2         # t5 = idx (0..9)
    slli t5, t5, 2          # offset bytes

    # x_candidate
    la   a3, apple_pos_x_table
    add  a3, a3, t5
    lw   a4, 0(a3)
    mv   t6, a4             # t6 = x_cand

    # y_candidate
    la   a3, apple_pos_y_table
    add  a3, a3, t5
    lw   a4, 0(a3)
    mv   t1, a4             # t1 = y_cand

    # --- comprobar que no cae sobre el cuerpo ---
    la   a3, snake_len
    lw   a4, 0(a3)          # a4 = snake_len
    li   a3, 0              # i = 0

body_loop:
    bge  a3, a4, found      # no hubo colisión

    slli t5, a3, 2          # offset = i*4

    # snake_x[i]
    la   t0, snake_x
    add  t0, t0, t5
    lw   t2, 0(t0)
    bne  t2, t6, next_body

    # snake_y[i]
    la   t0, snake_y
    add  t0, t0, t5
    lw   t2, 0(t0)
    beq  t2, t1, collides   # misma casilla -> probar otra posición

next_body:
    addi a3, a3, 1
    j    body_loop

collides:
    addi t4, t4, 1
    j    outer_loop

found:
    # posición aceptada t6,t1
    la   t0, apple_x
    sw   t6, 0(t0)
    la   t0, apple_y
    sw   t1, 0(t0)
    jr   ra

fallback:
    # por si todo falla (muy improbable): (1,1)
    li   t6, 1
    li   t1, 1
    la   t0, apple_x
    sw   t6, 0(t0)
    la   t0, apple_y
    sw   t1, 0(t0)
    jr   ra

#---------------------------------
# LECTURA DEL D-PAD -> s2
#---------------------------------
read_input:
    # UP
    li t0, 0xf0000dac
    lw t1, 0(t0)
    bnez t1, set_up

    # DOWN
    li t0, 0xf0000db0
    lw t1, 0(t0)
    bnez t1, set_down

    # LEFT
    li t0, 0xf0000db4
    lw t1, 0(t0)
    bnez t1, set_left

    # RIGHT
    li t0, 0xf0000db8
    lw t1, 0(t0)
    bnez t1, set_right

    jr ra

set_up:
    li s2, 0
    la t3, dir
    sw s2, 0(t3)
    jr ra

set_down:
    li s2, 1
    la t3, dir
    sw s2, 0(t3)
    jr ra

set_left:
    li s2, 2
    la t3, dir
    sw s2, 0(t3)
    jr ra

set_right:
    li s2, 3
    la t3, dir
    sw s2, 0(t3)
    jr ra

#---------------------------------
# MOVER CABEZA SEGÚN s2
#---------------------------------
move_snake:
    mv t0, s2          # t0 = dir

    beq t0, zero, move_up_dir

    li t1, 1
    beq t0, t1, move_down_dir

    li t1, 2
    beq t0, t1, move_left_dir

    li t1, 3
    beq t0, t1, move_right_dir

    jr ra

move_up_dir:
    addi s1, s1, -1
    jr ra

move_down_dir:
    addi s1, s1, 1
    jr ra

move_left_dir:
    addi s0, s0, -1
    jr ra

move_right_dir:
    addi s0, s0, 1
    jr ra

#---------------------------------
# GUARDAR COLA VIEJA (ANTES DE MOVER EL CUERPO)
#---------------------------------
get_old_tail:
    la t0, snake_len
    lw t1, 0(t0)          # t1 = snake_len
    addi t1, t1, -1       # tail_idx = len-1
    blt  t1, zero, got_tail_end

    slli t2, t1, 2        # offset = tail_idx*4

    # tail_x
    la  t3, snake_x
    add t3, t3, t2
    lw  t4, 0(t3)
    la  t5, old_tail_x
    sw  t4, 0(t5)

    # tail_y
    la  t3, snake_y
    add t3, t3, t2
    lw  t4, 0(t3)
    la  t5, old_tail_y
    sw  t4, 0(t5)

got_tail_end:
    jr ra

#---------------------------------
# BORRAR COLA VIEJA SI NO COMIÓ MANZANA
#---------------------------------
erase_tail_if_needed:
    la t0, ate_flag
    lw t1, 0(t0)
    bnez t1, erase_tail_end   # si comió, no borrar cola (crece)

    # cargar old_tail_x, old_tail_y
    la  t0, old_tail_x
    lw  t2, 0(t0)             # x
    la  t0, old_tail_y
    lw  t3, 0(t0)             # y

    # addr = base + (y*width + x)*4
    mul t4, t3, a1
    add t4, t4, t2
    slli t4, t4, 2
    add t4, a0, t4

    lw  t5, COLOR_BLACK
    sw  t5, 0(t4)

erase_tail_end:
    jr ra

#---------------------------------
# CHEQUEAR BORDES
#---------------------------------
check_bounds:
    blt s0, zero, game_over
    blt s1, zero, game_over
    bge s0, a1, game_over
    bge s1, a2, game_over
    jr ra

#---------------------------------
# ACTUALIZAR POSICIONES DEL CUERPO
#---------------------------------
update_snake_position:
    la t0, snake_len
    lw t1, 0(t0)          # t1 = snake_len
    addi t1, t1, -1       # último índice

move_loop:
    bge  zero, t1, save_head   # si t1 <= 0, salir

    slli t2, t1, 2

    # snake_x[t1] = snake_x[t1-1]
    la  t3, snake_x
    add t3, t3, t2
    lw  t4, -4(t3)
    sw  t4, 0(t3)

    # snake_y[t1] = snake_y[t1-1]
    la  t3, snake_y
    add t3, t3, t2
    lw  t4, -4(t3)
    sw  t4, 0(t3)

    addi t1, t1, -1
    j move_loop

save_head:
    la t0, snake_x
    sw s0, 0(t0)
    la t0, snake_y
    sw s1, 0(t0)
    jr ra

#---------------------------------
# COMER MANZANA (marcar ate_flag y crecer)
#---------------------------------
check_apple:
    la   t0, apple_x
    lw   t1, 0(t0)      # apple_x
    la   t0, apple_y
    lw   t2, 0(t0)      # apple_y

    bne  s0, t1, no_apple
    bne  s1, t2, no_apple

    # --- La cabeza está en la manzana ---

    # snake_len++
    la   t0, snake_len
    lw   t3, 0(t0)
    addi t3, t3, 1
    sw   t3, 0(t0)

    # ate_flag = 1
    la   t0, ate_flag
    li   t4, 1
    sw   t4, 0(t0)

    # respawn apple preservando ra
    mv   s3, ra
    jal  respawn_apple
    mv   ra, s3
    jr   ra

no_apple:
    jr   ra

#---------------------------------
# DELAY (ajusta a gusto)
#---------------------------------
game_delay:
    li t0, 5        # baja si va muy lento
delay_loop:
    addi t0, t0, -1
    bnez t0, delay_loop
    jr ra

#---------------------------------
# FIN DEL JUEGO
#---------------------------------
game_over:
halt_loop:
    j halt_loop
