.data

input_addr:                .word 0x80                ;адреса ввода
output_addr:               .word 0x84                ;адрес вывода
ret_stack_top_addr:        .word 0x1000              ;адрес верхушки стека возврата
calc_stack_top_addr:       .word 0x800               ;адрес верхушки стека калькулятора

plus_symbol:               .word 0x2B                ;коды символов арифметических операторов
minus_symbol:              .word 0x2D
mult_symbol:               .word 0x2A
div_symbol:                .word 0x2F

space_symbol:              .word 0x20                ;коды символов пробела и перехода на новую строку
new_line_symbol:           .word 0xA

ascii_0_code:              .word 0x30
ascii_9_code:              .word 0x39
max_symbols:               .word 64                  ;нужно дял одного из тестов

overflow_error_value:       .word 0xCCCC_CCCC         ;значения при исключениях программы
zero_div_error_value:      .word -1                  ;деление на 0
invalid_expr_error_value:  .word -1

;A0 - адресный регистр вывода
;A1 - адресный регистр ввода
;A5 - указатель стека калькулятора
;A6 - указатель фрейма для подпрограммы
;A7 - указатель стека просто

;D0 - регистр для ввода и вывода
;D1 - регистр для размера стека
;D2 - регистр для кода ошибки
;D3 и D4 - регистры для работы с данными стека(типа T и S в F32A)
;D5 - регистр для накопления текущего числа
;D6 - регистр с финальным ответом и счетчиком символов
;D7 - регистр флаг который показывает, накапливает ли D5 число в себе


.text
.org 0x88

_start:
    movea.l ret_stack_top_addr, A1          ;получаем адрес значения верхушки стека возврата
    movea.l (A1), A7                        ;сетпаим верхушку стека возврата(или низушку хз)

    jsr setup                               ;реализация процедур, так красиво
    jsr main
    jsr finish
    halt

setup:
    movea.l calc_stack_top_addr, A1         ;получаем адрес значения верхушки стека калькулятора
    movea.l (A1), A5                        ;сетпаим верхушку стека калькулятора(или низушку хз)

    clr.l D0                                ;очищаем регистры данных на всякий случай
    clr.l D1
    clr.l D2
    clr.l D3
    clr.l D4
    clr.l D5
    clr.l D6
    clr.l D7
    rts

main:
    link A6, 0                              ;делаем локальный стек

input_loop:
    movea.l max_symbols, A1                 ;получаем адрес лимита символов
    cmp.l (A1), D6                          ;проверяем лимит символов
    beq input_overflow

    add.l 1, D6                             ;увеличиваем счетчик прочитанных символов

    movea.l input_addr, A1                  ;получаем адрес значения input_addr
    movea.l (A1), A0                        ;читаем некий символ
    move.l (A0), D0

    movea.l new_line_symbol, A1             ;получаем адрес кода новой строки
    cmp.l (A1), D0                          ;сразу проверяем вдруг это конец уже
    beq new_line_parse

    cmp.l 0, D2                             ;чекаем, есть ли ошибка, если да, то пропускаем всю работу с символом
    bne shortcut

    jsr operand_parse                       ;вызываем парсинг того что прочитали

shortcut:
    jmp input_loop

finish:
    movea.l output_addr, A1                 ;получаем адрес значения output_addr
    movea.l (A1), A0

    cmp.l 0, D2                             ;проверяем код ошибки, если 0 то норм
    bne return_error                        ;если нет, то печатаем код ошибки

    move.l (A5)+, D6                        ;достали финальный результат
    move.l D6, (A0)
    rts

return_error:
    move.l D2, (A0)
    rts

operand_parse:
    movea.l plus_symbol, A1                 ;получаем адрес кода плюса
    cmp.l (A1), D0                          ;проверка на плюс
    beq operator_parse

    movea.l minus_symbol, A1                ;получаем адрес кода минуса
    cmp.l (A1), D0                          ;проверка на минус
    beq operator_parse

    movea.l mult_symbol, A1                 ;получаем адрес кода умножения
    cmp.l (A1), D0                          ;проверка на умножение
    beq operator_parse

    movea.l div_symbol, A1                  ;получаем адрес кода деления
    cmp.l (A1), D0                          ;проверка на деление
    beq operator_parse

    movea.l space_symbol, A1                ;получаем адрес кода пробела
    cmp.l (A1), D0                          ;проверка на пробел
    beq space_parse

    movea.l ascii_0_code, A1                ;получаем адрес кода 0
    cmp.l (A1), D0                          ;проверяем что попали в диапазон 0-9
    blt set_invalid_expr

    movea.l ascii_9_code, A1                ;получаем адрес кода 9
    cmp.l (A1), D0
    bgt set_invalid_expr

    movea.l ascii_0_code, A1                ;снова получаем код 0
    sub.l (A1), D0                          ;переводим код цифры в число

    mul.l 10, D5
    bvs set_overflow

    add.l D0, D5
    bvs set_overflow

    move.l 1, D7                            ;в D5 теперь набирается число
    rts

operator_parse:
    cmp.l 2, D1                             ;проверяем что размер стека хотя бы 2
    blt set_invalid_expr

    move.l (A5)+, D4                        ;кладем операнды в D3 и D4, то есть получаем упорядоченный набор (D3, D4)
    move.l (A5)+, D3

    sub.l 2, D1                             ;вычитаем 2 из размера стека(попнули 2 операнда)

    movea.l plus_symbol, A1                 ;получаем адрес кода плюса
    cmp.l (A1), D0                          ;проверка на плюс
    beq plus_parse

    movea.l minus_symbol, A1                ;получаем адрес кода минуса
    cmp.l (A1), D0                          ;проверка на минус
    beq minus_parse

    movea.l mult_symbol, A1                 ;получаем адрес кода умножения
    cmp.l (A1), D0                          ;проверка на умножение
    beq mult_parse

    movea.l div_symbol, A1                  ;получаем адрес кода деления
    cmp.l (A1), D0                          ;проверка на деление
    beq div_parse

plus_parse:
    add.l D4, D3
    jmp operand_post_parse

minus_parse:
    sub.l D4, D3
    jmp operand_post_parse

mult_parse:
    mul.l D4, D3
    jmp operand_post_parse

div_parse:
    cmp.l 0, D4                             ;проверка на деление на 0
    beq set_zero_div

    div.l D4, D3
    jmp operand_post_parse

operand_post_parse:
    bvs set_overflow                         ;проверка на OF

    move.l D3, -(A5)                        ;положили в стек результат и увеличили размер на 1
    add.l 1, D1
    rts

space_parse:
    cmp.l 0, D7                             ;если D7 = 0 сейчас число не набирается
    beq space_return                        ;значит просто игнорируем пробел

    jsr stack_push                          ;иначе пушим накопленное число

space_return:
    rts

stack_push:
    move.l D5, -(A5)                        ;пушим текущее число в стек калькулятора
    add.l 1, D1                             ;увеличиваем размер стека

    clr.l D5                                ;готовы накапливать следующее число
    clr.l D7                                ;текущего незапушенного числа больше нет
    rts

new_line_parse:
    cmp.l 0, D2                             ;проверяем была ли ошибка во время вычислений
    bne return                              ;если была, то просто завершаем main

    cmp.l 0, D7                             ;проверяем осталось ли незапушенное число
    beq final_check

    jsr stack_push                          ;пушим последнее число в стек

final_check:
    cmp.l 1, D1                             ;проверяем что в стеке остался ровно один результат
    beq return

    movea.l invalid_expr_error_value, A1    ;получаем адрес значения ошибки
    move.l (A1), D2                         ;ставим ошибку некорректного выражения
    jmp return

return:
    unlk A6                                 ;восстанавливаем фрейм main
    rts

set_invalid_expr:
    movea.l invalid_expr_error_value, A1    ;получаем адрес значения ошибки
    move.l (A1), D2                         ;ставим ошибку некорректного выражения
    rts

set_overflow:
    movea.l overflow_error_value, A1        ;получаем адрес значения ошибки
    move.l (A1), D2                         ;ставим ошибку переполнения
    rts

set_zero_div:
    movea.l zero_div_error_value, A1        ;получаем адрес значения ошибки
    move.l (A1), D2                         ;ставим ошибку деления на 0
    rts

input_overflow:
    movea.l overflow_error_value, A1        ;получаем значение ошибки переполнения
    move.l (A1), D2
    jmp return                             ;завершаем main не читая следующий символ