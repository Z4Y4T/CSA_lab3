.text
_start
@p 0x80 a!                          \чтение регистра ввода
@p 0x80

lit 0x1F and                        \взятие по модулю 32
lit 32 over inv lit 0x1 + +         \расчет 32-n для второго цикла
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

+ !p 0x84