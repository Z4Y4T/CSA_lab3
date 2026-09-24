    .data
.org             0x88
input_addr:      .word  0x80               ;адрес ввода данных
output_addr:     .word  0x84               ;адрес вывода данных
counter:         .word  0x0                ;счетчик n
exponent:        .word  0x0                ;счетчик для степени
base:            .word  0x0                ;основание для перемножения
result:          .word  0x0                ;результат операций
const_1:         .word  0x1                ;единица чтоб отнимать от счетчиков
const_4:         .word  0x4                ;четверка для указателя
error_code:      .word  0x0                ;код ошибки

buffer_start:    .word  0x300              ;буфер чтобы сохранять результаты
buffer_pointer:  .word  0x300              ;нужно чтобы проглотить ввод в случае ошибки
buffer_counter:  .word  0x0

    .text
_start:
    load         input_addr                  ;читаем ввод(счетчик n)
    load_acc
    store_addr   buffer_counter              ;сохраняем счетчик для буфера и просто
    store_addr   counter

    bltz         invalid_n_exception         ;проверка корректности счетчика(n>=0)
    beqz         invalid_n_exception

input_loop:
    load         counter                     ;вычитаем счетчик n
    sub          const_1
    store_addr   counter

    load         input_addr                  ;считывание основания
    load_acc
    store_addr   base

    load         input_addr                  ;считывание степени
    load_acc
    bltz         invalid_exp_exception
    store_addr   exponent

    load_imm     0x1                         ;подготовка результата
    store_addr   result

    load         exponent
    beqz         exp_loop_end                ;случай если степень равна нулю

exp_loop:
    load         exponent                    ;вычитаем счетчик степени
    sub          const_1
    store_addr   exponent

    load         result                      ;умножение основания
    mul          base
    bvs          out_of_bounds_exception     ;если переполнили лимит в 32 бита, то переход на СС
    store_addr   result

    load         exponent                    ;проверка на конец
    bnez         exp_loop

exp_loop_end:
    load         result                      ;выгружаем результат
    store_ind    buffer_pointer              ;сохраняем в буфер
    load         buffer_pointer              ;двигаем указатель буфера
    add          const_4
    store_addr   buffer_pointer
    load         counter
    bnez         input_loop

exception_handling:
    load         error_code                  ;читаем ошибку и выводим ее если она есть
    beqz         prepare_output
    store_ind    output_addr
    jmp          finish

prepare_output:
    load         buffer_start                ;возвращаем указатель буфера в начало
    store_addr   buffer_pointer

output_loop:
    load         buffer_pointer              ;выводим из буфера результаты
    load_acc
    store_ind    output_addr
    load         buffer_pointer
    add          const_4
    store_addr   buffer_pointer
    load         buffer_counter
    sub          const_1
    store_addr   buffer_counter
    bnez         output_loop

finish:
    halt

    ;если вышли за пределы 32 бит, возвращаем 0xCCCCCCCC
out_of_bounds_exception:
    load_imm     0xCCCC_CCCC
    store_addr   error_code
    jmp          discard_start

    ;если n не в диапазоне, возвращаем -1
invalid_n_exception:
    load_imm     -1
    store_ind    output_addr
    jmp          finish

    ;если степень не в диапазоне, возвращаем -1
invalid_exp_exception:
    load_imm     -1
    store_addr   error_code
    jmp          discard_start

    ;дочитываем оставшиеся пары после ошибки
discard_start:
    load         counter
    beqz         exception_handling

discard_loop:
    load         input_addr                  ;считываем и выбрасываем основание
    load_acc

    load         input_addr                  ;считываем и выбрасываем степень
    load_acc

    load         counter                     ;вычитаем счетчик оставшихся пар
    sub          const_1
    store_addr   counter
    bnez         discard_loop
    jmp          exception_handling
