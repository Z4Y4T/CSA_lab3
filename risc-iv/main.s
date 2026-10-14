.data

input_addr:          .word 0x80
output_addr:         .word 0x84
buf_start_addr:      .word 0x0
stack_top_addr:      .word 0x500

buf_size:            .word 0x20

question_size:       .word 19
answer_size:         .word 7
excl_mark_size:      .word 1

overflow_error_value: .word 0xCCCCCCCC

new_line:            .byte 0xA

question_message:    .byte 'What is your name?\n'
answer_message:      .byte 'Hello, '
excl_mark:           .byte '!'

; s1 - размер постоянной части ответа "Hello, " + "!"
; s2 - input_addr
; s3 - output_addr
; s4 - код '\n'
; s5 - максимальная длина имени
; s6 - начало буфера

; a0-a2 - аргументы функций и возвращаемые значения

; t0-t1 - временные регистры


.org 0x88
.text

_start:
    j       boot

boot:
    lui     t0, %hi(input_addr)             ; расчехляем регистр под input_addr
    addi    t0, t0, %lo(input_addr)
    lw      s2, 0(t0)

    lui     t0, %hi(output_addr)            ; расчехляем регистр под output_addr
    addi    t0, t0, %lo(output_addr)
    lw      s3, 0(t0)

    lui     t0, %hi(new_line)               ; расчехляем код '\n'
    addi    t0, t0, %lo(new_line)
    lb      s4, 0(t0)

    lui     t0, %hi(buf_start_addr)         ; расчехляем начало буфера
    addi    t0, t0, %lo(buf_start_addr)
    lw      s6, 0(t0)

    lui     t0, %hi(answer_size)            ; расчехляем размер постоянной части ответа
    addi    t0, t0, %lo(answer_size)
    lw      s1, 0(t0)                       ; s1 = 7

    lui     t0, %hi(excl_mark_size)
    addi    t0, t0, %lo(excl_mark_size)
    lw      t1, 0(t0)

    add     s1, s1, t1                      ; s1 = 7 + 1 = 8

    lui     t0, %hi(buf_size)               ; расчехляем максимальную длину имени
    addi    t0, t0, %lo(buf_size)
    lw      s5, 0(t0)                       ; s5 = 32

    sub     s5, s5, s1                      ; вычитаем "Hello, " + "!"
    addi    s5, s5, -1                      ; еще один байт нужен под длину Pascal string
                                            ; s5 = 23

    lui     t0, %hi(stack_top_addr)         ; расчехляем верхушку стека
    addi    t0, t0, %lo(stack_top_addr)
    lw      sp, 0(t0)                       ; sp = 0x500

    mv      t0, s6                          ; начинаем с buffer[0]
    addi    t1, zero, 0x20                  ; всего 32 байта
    addi    t2, zero, 0x5f                  ; '_'

init_buffer:
    sb      t2, 0(t0)                       ; записываем '_'
    addi    t0, t0, 1                       ; следующий байт
    addi    t1, t1, -1                      ; уменьшаем счетчик
    bnez    t1, init_buffer

    j       program_start

program_start:
    jal     ra, main
    jal     ra, finish
    halt


main:
    addi    sp, sp, -4                      ; пушим ra на стек
    sw      ra, 0(sp)

    jal     ra, print_question              ; сначала задаем пользователю вопрос

    ; теперь копируем "Hello, " в Pascal-буфер
    ; buffer[0] пока оставляем под длину строки
    lui     a0, %hi(answer_message)         ; a0 = откуда копируем "Hello, "
    addi    a0, a0, %lo(answer_message)
    addi    a1, s6, 1                       ; a1 = buffer + 1 (buffer[0] оставляем под длину)

    lui     a2, %hi(answer_size)            ; a2 = количество символов
    addi    a2, a2, %lo(answer_size)
    lw      a2, 0(a2)

    jal     ra, copy_message                ; после copy_message a1 = buffer + 8 то есть место первого символа имени

    mv      a0, a1                          ; читаем имя, a0 = куда записывать имя
    mv      a1, zero                        ; a1 = длина имени = 0

    jal     ra, input_message               ; после input_message a0 = адрес сразу после имени a1 = длина имени

    beqz    a1, main_error                  ; пустое имя или ov, значит ошибка

    lui     t0, %hi(excl_mark)              ; добавляем '!' после имени
    addi    t0, t0, %lo(excl_mark)
    lb      t0, 0(t0)

    sb      t0, 0(a0)

    add     t1, a1, s1                      ; формируем длину Pascal-строки, total_len = name_len + 8
    sb      t1, 0(s6)                       ; buffer[0] = total_len

    addi    a0, s6, 1                       ; выводим готовую Pascal-строку, сам байт длины не выводим, a0 = первый символ
    mv      a1, t1                          ; a1 = количество символов

    jal     ra, output_message

    j       main_end

main_error:
    lui     t0, %hi(overflow_error_value)    ; достаем код ошибки
    addi    t0, t0, %lo(overflow_error_value)
    lw      t0, 0(t0)

    sw      t0, 0(s3)                       ; выводим 0xCCCCCCCC в output_addr

main_end:
    lw      ra, 0(sp)                       ; попаем старый ra
    addi    sp, sp, 4

    jr      ra


print_question:                             ; print_question()
    addi    sp, sp, -4                      ; пушим адрес возврата в main
    sw      ra, 0(sp)

    lui     a0, %hi(question_message)       ; a0 = адрес вопроса
    addi    a0, a0, %lo(question_message)

    lui     a1, %hi(question_size)          ; a1 = длина вопроса
    addi    a1, a1, %lo(question_size)
    lw      a1, 0(a1)

    jal     ra, output_message              ; вложенный вызов процедуры

    lw      ra, 0(sp)                       ; возвращаем старый ra
    addi    sp, sp, 4

    jr      ra


output_message:                             ; output_message(a0=message_addr, a1=message_size) - выводит a1 байт начиная с адреса a0, a0 и a1 caller-saved, поэтому спокойно их залупим внутри функции
    beqz    a1, output_message_end          ; если все вывели ливаем

    lb      t0, 0(a0)                       ; достаем очередной символ
    sb      t0, 0(s3)                       ; отправляем его в output_addr

    addi    a0, a0, 1                       ; двигаемся к следующему байту
    addi    a1, a1, -1                      ; уменьшаем количество оставшихся символов

    j       output_message

output_message_end:
    jr      ra


copy_message:                               ; copy_message(a0=source, a1=destination, a2=size) - копирует a2 байт из a0 в a1, после функции a1 указывает сразу после последнего записанного байта
    beqz    a2, copy_message_end            ; если все скопировали, ливаем

    lb      t0, 0(a0)                       ; читаем символ из source
    sb      t0, 0(a1)                       ; записываем его в destination

    addi    a0, a0, 1                       ; двигаем оба указателя
    addi    a1, a1, 1

    addi    a2, a2, -1                      ; одним символом меньше осталось копировать

    j       copy_message

copy_message_end:
    jr      ra


input_message:                              ; input_message(a0=buf_addr, a1=0) - читает имя из input_addr до \n, при достижении лимита сразу возвращаем ошибку, не читая следующий символ
    lb      t0, 0(s2)                       ; читаем очередной символ

    beq     t0, s4, input_message_end       ; встретили \n значит строка закончилась

    sb      t0, 0(a0)                       ; записываем символ имени в буфер

    addi    a0, a0, 1                       ; двигаем указатель
    addi    a1, a1, 1                       ; увеличиваем длину имени

    beq     a1, s5, ov_exception            ; дошли до лимита 23 значит overflow

    j       input_message

input_message_end:
    jr      ra

ov_exception:
    mv      a1, zero                        ; a1 = 0 -> main поймет, что произошла ошибка
    jr      ra

finish:
    jr      ra