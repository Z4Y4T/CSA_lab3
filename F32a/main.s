.text

_start:
boot
main
finish
halt

boot:
@p 0x80 a!                          \чтение регистра ввода
@p 0x80

lit 0x1F and                        \взятие по модулю 32
;

main:
dup if zero_shift                   \проверка n=0
lit 0xFFFF_FFFF +                   \вычитане единицы(изза устройства циклов)

lit 30 over inv lit 0x1 + +         \расчет 31-n для второго цикла(31 изза устройства циклов)
over

>r                                  \пихаем n в стек возврата для цикла
a                                   \кладем число наверх

loop_shift_right:
2/ lit 0x7FFF_FFFF and              \двигаем вправо, и маской обнуляем левый бит
next loop_shift_right               \делаем цикл по n

over >r                             \кладем в стек возврата 32-n для второго цикла
a                                   \кладем число наверх

loop_shift_left:
2*                                  \двигаем влево
next loop_shift_left                \терпим

+ a!                                \складываем правый и левый сдвиги и сохраняем в АААА
drop drop                           \чистим чистим
;

zero_shift:
drop                                \убираем shift=0 со стека
;

finish:
a !p 0x84                           \мы победили
;