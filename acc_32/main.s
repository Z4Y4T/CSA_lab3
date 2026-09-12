.data
.org 0x90
    input_addr: .word 0x80       ;адрес ввода данных
    output_addr: .word 0x84      ;адрес вывода данных
    counter: .word 0x0           ;счетчик n
    exponent: .word 0x0          ;счетчик для степени
    base: .word 0x0              ;основание для перемножения
    result: .word 0x0            ;результат операций
    const_1: .word 0x1           ;единица чтоб отнимать от счетчиков
    const_4: .word 0x4           ;четверка для указателя
    error_code: .word 0x0        ;код ошибки

    buffer_start: .word 0x300    ;буфер чтобы сохранять результаты
    buffer_pointer: .word 0x300
    buffer_counter: .word 0x0

.text
_start:
    load input_addr
    load_acc
    store_addr buffer_counter
    store_addr counter

    bltz invalid_n_exception    ;проверка корректности счетчика
    beqz invalid_n_exception

main_loop:
    load counter                ;вычитаем счетчик n
    sub const_1
    store_addr counter

    load input_addr             ;считывание основания
    load_acc
    store_addr base

    load input_addr             ;считывание степени
    load_acc
    bltz invalid_exp_exception
    store_addr exponent

    load_imm 0x1                ;подготовка результата
    store_addr result

    load exponent
    beqz end_exp_loop           ;случай если степень равна нулю
    
exp_loop:
    load exponent               ;вычитаем счетчик степени
    sub const_1
    store_addr exponent

    load result                 ;умножение основания
    mul base
    bvs out_of_bounds           ;если переполнили лимит в 32 бита, то переход
    store_addr result

    load exponent
    beqz end_exp_loop           ;проверка на конец
    jmp exp_loop

end_exp_loop:
    load result                 ;выгружаем результат
    store_ind buffer_pointer    ;сохраняем в буфер
    load buffer_pointer         ;двигаем указатель буфера
    add const_4
    store_addr buffer_pointer
    load counter
    beqz end
    jmp main_loop

end:
    load error_code             ;читаем ошибку и выводим ее если она есть
    beqz prepare_output
    store_ind output_addr
    halt

prepare_output:
    load buffer_start           ;возвращаем указатель буфера в начало
    store_addr buffer_pointer

end_loop:
    load buffer_pointer         ;выводим из буфера результаты
    load_acc
    store_ind output_addr
    load buffer_pointer
    add const_4
    store_addr buffer_pointer
    load buffer_counter
    sub const_1
    store_addr buffer_counter
    bnez end_loop
    halt

out_of_bounds:                  ;если вышли за пределы 32 бит, возвращаем 0xcccccccc
    load_imm 0xCCCC_CCCC
    store_addr error_code
    jmp exception_handler

invalid_n_exception:            ;если n не в диапазоне, возвращаем -1 и халтим
    load_imm -1
    store_ind output_addr
    halt

invalid_exp_exception:          ;если степень не в диапазоне, возвращаем -1
    load_imm -1
    store_addr error_code
    jmp exception_handler

exception_handler:              ;дочитываем оставшиеся пары после ошибки
    load counter
    beqz end

discard_loop:
    load input_addr             ;считываем и выбрасываем основание
    load_acc

    load input_addr             ;считываем и выбрасываем степень
    load_acc

    load counter                ;вычитаем счетчик оставшихся пар
    sub const_1
    store_addr counter
    bnez discard_loop
    jmp end