 .data
input_addr:      .word  0x80                        \адрес ввода
output_addr:     .word  0x84                        \адрес вывода
shift_mask:      .word  0x1F
left_counter_base: .word  0x1E
logical_shift_mask: .word  0x7FFF_FFFF              \маска чтоб срезать левый бит
const_one:       .word  0x1
const_minus_one: .word  0xFFFF_FFFF

 .text

_start:
    boot
    main
    finish
    halt

boot:
    @p input_addr b! @b a! @b                       \чтение регистра ввода
    @p shift_mask and                               \взятие по модулю 32
    ;

main:
    dup if zero_shift                               \проверка n=0
    @p const_minus_one +                            \вычитане единицы(изза устройства циклов)

    @p left_counter_base over inv @p const_one + +  \расчет 31-n для второго цикла(31 изза устройства циклов)
    over

    >r                                              \пихаем n в стек возврата для цикла
    a                                               \кладем число наверх

loop_shift_right:
    2/ @p logical_shift_mask and                    \двигаем вправо, и маской обнуляем левый бит
    next loop_shift_right                           \делаем цикл по n

    over >r                                         \кладем в стек возврата 32-n для второго цикла
    a                                               \кладем число наверх

loop_shift_left:
    2*                                              \двигаем влево
    next loop_shift_left                            \терпим

    + a!                                            \складываем правый и левый сдвиги и сохраняем в АААА
    drop drop                                       \чистим чистим
    ;

zero_shift:
    drop                                            \убираем shift=0 со стека
    ;

finish:
    @p output_addr b!
    a !b                                            \мы победили
    ;