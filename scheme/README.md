# F32A Neumann Microcode — RTL-схема процессора

Этот README описывает выбранную микроархитектуру варианта **`f32a-neumann-microcode`**: состав datapath, назначение регистров и стеков, память и MMIO, ALU, общую шину данных, управляющие сигналы, формат микроинструкции и устройство микропрограммного Control Unit.

> Важно: ISA F32A задаёт **поведение инструкций**, но не единственную обязательную аппаратную реализацию. Ниже описана конкретная RTL-реализация, выбранная для схемы. Там, где речь идёт о поведении команд, мы следуем F32A/Wrench; там, где речь идёт о регистрах MDR, кэшировании T/S/R, формате микрокоманды и т.п., это уже микроархитектурные решения данной схемы.

---

## Оглавление

1. [Общая идея архитектуры](#sec-1)
2. [Register File и основные регистры](#sec-2)
3. [Data Stack и Return Stack](#sec-3)
4. [Memory Segment](#sec-4)
5. [Data Bus и Output Enable](#sec-5)
6. [ALU Segment](#sec-6)
7. [Операции ALU](#sec-7)
8. [Carry и EAM](#sec-8)
9. [Control Unit](#sec-9)
10. [Формат микроинструкции](#sec-10)
11. [Управляющие сигналы datapath](#sec-11)
12. [Fetch машинной инструкции](#sec-12)
13. [Как исполняются основные группы инструкций](#sec-13)
14. [Простая арифметика](#sec-14)
15. [Multiply Step `+*`](#sec-15)
16. [Divide Step `+/`](#sec-16)
17. [Stack instructions](#sec-17)
18. [Control-flow instructions](#sec-18)
19. [Почему архитектура считается функционально полной](#sec-19)
20. [Что является внутренней реализацией и не рисуется](#sec-20)
21. [Что важно уметь объяснить на защите](#sec-21)
22. [Краткая шпаргалка по всей схеме](#sec-22)
23. [Источники](#sec-23)

---

<a id="sec-1"></a>
## 1. Общая идея архитектуры

F32A — 32-битная стековая архитектура с двумя стеками:

- **Data Stack** — основной стек данных;
- **Return Stack** — стек возвратов;
- архитектурные регистры **A** и **B**;
- вершина Data Stack обозначается **T**, второй элемент — **S**;
- вершина Return Stack обозначается **R**;
- есть состояния **Carry** и **EAM (Extended Arithmetic Mode)**;
- используется memory-mapped I/O.

Вариант **Neumann** означает, что инструкции и обычные данные находятся в общей памяти RAM. Стековые backing memory (`DS_MEM`, `RS_MEM`) являются локальной памятью datapath и не заменяют основную RAM.

Вся схема разбита на четыре логические части:

1. **Register File / Stack subsystem**
2. **Memory Segment**
3. **ALU Segment**
4. **Control Unit**

Центральная передача результатов выполняется через общую **Data Bus**.

---

<a id="sec-2"></a>
# 2. Register File и основные регистры

## 2.1. A и B

`A` и `B` — основные 32-битные регистры F32A.

Используются, в частности:

- `A` — адресация команд `@`, `@+`, `!`, `!+`;
- `B` — адресация команд `@b`, `!b`;
- `A` участвует в `+*` и `+/`;
- `B` используется в `+/` как адрес делителя `mem[B]`.

Запись:

```text
latch_a
latch_b
```

Чтение происходит постоянно с выхода регистра; дальнейший выбор нужного источника выполняют MUX перед ALU.

---

## 2.2. PC

`PC` — Program Counter, адрес машинной инструкции в общей RAM.

Он должен позволять:

- перейти к следующему opcode;
- пропустить operand;
- выполнить jump/call/if/-if/next;
- сформировать return address для `call`.

В ALU предусмотрены операции с внутренней добавкой `+1`, `+5`, поэтому отдельные аппаратные константы `1` и `5` перед ALU не нужны.

Запись в PC разрешается сигналом:

```text
latch_pc
```

---

## 2.3. IR

`IR` — Instruction Register.

F32A использует:

```text
1 byte opcode
4 bytes per argument
```

IR нужен прежде всего для хранения текущего opcode, который поступает в Control Unit и определяет, какая микропрограмма должна исполняться.

Запись:

```text
latch_ir
```

---

## 2.4. MDR

`MDR` — Memory Data Register, 32-битный буфер данных памяти.

Он введён не как архитектурный регистр F32A, а как микроархитектурный временный регистр.

Он полезен для:

- хранения 4-байтового operand машинной инструкции;
- сохранения значения, прочитанного из RAM, на несколько микротактов;
- `+/`, где удобно один раз загрузить `mem[B]` и дальше работать с делителем из MDR;
- промежуточных преобразований, например `INV` при реализации вычитания через дополнительный код.

Запись:

```text
latch_mdr
```

MDR также является одним из источников правого ALU MUX.

---

<a id="sec-3"></a>
# 3. Data Stack и Return Stack

## 3.1. Почему T, S и R нарисованы регистрами

Архитектурно:

- `T` — вершина Data Stack;
- `S` — второй элемент Data Stack;
- `R` — вершина Return Stack.

Микроархитектурно они реализованы как быстрые регистры-кэши верхних элементов стеков.

Остальные значения находятся в:

```text
DS_MEM
RS_MEM
```

Это позволяет большинству арифметических операций использовать `T`, `S` и `R` без обращения к локальной памяти стека.

---

## 3.2. DSP и RSP

`DSP` и `RSP` трактуются как **логическая глубина стека**, а не буквально как непосредственный адрес ячейки backing memory.

Управление:

```text
op_dsp : 2 bits
op_rsp : 2 bits
```

Принятое кодирование:

```text
00 — HOLD
01 — PUSH / INC
10 — POP  / DEC
11 — reserved
```

Внутренняя логика Stack Segment по глубине сама определяет:

- нужен ли доступ к `DS_MEM` / `RS_MEM`;
- чтение это или запись;
- какой внутренний адрес backing memory использовать;
- нужно ли выполнять spill/fill.

Поэтому отдельные `ds_re`, `ds_we`, `rs_re`, `rs_we` не входят в формат микроинструкции.

---

## 3.3. Data Stack: T и S

Для Data Stack два верхних элемента кэшированы:

```text
T — top
S — second
```

### PUSH

Концептуально:

```text
depth = 0:
    new -> T
    DSP++

depth = 1:
    old T -> S
    new   -> T
    DSP++

depth >= 2:
    old S -> DS_MEM
    old T -> S
    new   -> T
    DSP++
```

То есть первые два push не требуют записи в `DS_MEM`.

### POP

```text
depth = 1:
    удалить T
    DSP--

depth = 2:
    S -> T
    DSP--

depth > 2:
    S -> T
    DS_MEM -> S
    DSP--
```

Обращение к backing memory требуется только когда под кэшированными `T/S` действительно есть дополнительные элементы.

---

## 3.4. Return Stack: R

Для Return Stack кэшируется только верхний элемент:

```text
R — top of return stack
```

### PUSH

```text
depth = 0:
    new -> R

depth >= 1:
    old R -> RS_MEM
    new   -> R
```

### POP

```text
depth = 1:
    удалить R

depth > 1:
    RS_MEM -> R
```

---

## 3.5. S_MUX и R_MUX

`S_MUX` и `R_MUX` позволяют выбирать источник нового значения соответствующего cached-top регистра.

Для обоих достаточно двух вариантов, поэтому:

```text
sel_s : 1 bit
sel_r : 1 bit
```

Отдельный `T_MUX` не используется: нужные значения можно доставить в T через общий datapath/Data Bus и ALU.

---

<a id="sec-4"></a>
# 4. Memory Segment

Memory Segment содержит:

```text
MAR
Address Decoder
RAM
MM_IN_REG
MM_OUT_REG
RD_MUX
```

---

## 4.1. MAR

`MAR` — Memory Address Register.

Он хранит адрес текущего обращения к общей памяти/MMIO.

Запись:

```text
latch_mar
```

MAR одновременно подаётся:

- на адресный вход RAM;
- в Address Decoder.

---

## 4.2. Address Decoder

Control Unit выдаёт только общую операцию:

```text
mem_re
mem_we
```

Address Decoder анализирует `MAR` и выбирает конкретное устройство.

В принятой учебной конфигурации:

```text
0x80 — input MMIO
0x84 — output MMIO
остальные допустимые адреса — RAM
```

Внутренне decoder формирует сигналы вроде:

```text
ram_re
ram_we
mm_in_re
mm_out_we
sel_rd
```

Они **не являются отдельными полями микроинструкции**, потому что выводятся комбинационно из `MAR`, `mem_re` и `mem_we`.

---

## 4.3. MM_IN_REG

`MM_IN_REG` представляет memory-mapped input.

Направление:

```text
external input -> MM_IN_REG -> RD_MUX -> Data Bus
```

CPU не записывает `MM_IN_REG`.

---

## 4.4. MM_OUT_REG

`MM_OUT_REG` представляет memory-mapped output.

Направление:

```text
Data Bus -> MM_OUT_REG -> external output
```

Запись разрешается внутренним `mm_out_we`, сформированным Address Decoder.

---

## 4.5. RD_MUX

При чтении источник может быть:

```text
RAM.rdata
MM_IN_REG
```

`RD_MUX` выбирает нужный вариант по `sel_rd`, который формируется Address Decoder.

После `RD_MUX` данные поступают к общей Data Bus.

---

<a id="sec-5"></a>
# 5. Data Bus и Output Enable

На общую Data Bus могут выдавать данные как минимум два блока:

```text
ALU
RD_MUX
```

Нельзя просто заставить неиспользуемый источник выдавать `0`: ноль всё равно является активным электрическим значением и создаст конфликт с другим драйвером.

Поэтому используются:

```text
alu_oe : 1 bit
rd_oe  : 1 bit
```

Логика:

```text
alu_oe rd_oe
   0      0   никто не управляет Data Bus
   1      0   Data Bus <- ALU
   0      1   Data Bus <- RD_MUX
   1      1   запрещённая комбинация
```

Корректный микрокод никогда не должен формировать последнюю комбинацию.

Это позволяет обойтись без отдельного большого `BUS_MUX`.

---

<a id="sec-6"></a>
# 6. ALU Segment

Перед ALU находятся три входных мультиплексора:

- `ALU_L_MUX` — левый 32-битный операнд;
- `ALU_R_MUX` — правый 32-битный операнд;
- `ALU_STATE_MUX` — дополнительный 1-битный вход состояния, выбирающий `Carry` или `EAM`.

`Carry` и `EAM` в текущей версии схемы **не поступают напрямую в `Next Microcommand Logic`**. Они являются состояниями datapath и подаются в ALU через третий MUX.

---

## 6.1. ALU_L_MUX

Левый MUX выбирает один из четырёх источников:

```text
S
A
R
PC
```

Поэтому:

```text
sel_lf : 2 bits
```

Отдельное нулевое состояние слева по итогам проверки datapath не требуется.

---

## 6.2. ALU_R_MUX

Правый MUX предоставляет:

```text
T
B
MDR
0
```

Ноль здесь нужен для унарных/константных арифметических преобразований вида:

```text
PC + 0 + 5
R  + 0 - 1
X  + 0 + 1
```

Поэтому:

```text
sel_rt : 2 bits
```

---

## 6.3. ALU_STATE_MUX

Третий MUX выбирает одно из двух 1-битных состояний процессора:

```text
Carry
EAM
```

Поэтому:

```text
sel_ce : 1 bit
```

Его выход является дополнительным 1-битным входом ALU. Он не является ещё одним 32-битным операндом: конкретная ALU-операция интерпретирует этот вход как требуемое состояние (`Carry` или `EAM`). Внутренняя логика использования этого входа на основной RTL-схеме не детализируется.

---

<a id="sec-7"></a>
# 7. Операции ALU

ALU остаётся **одним RTL-блоком**. Внутренние сумматоры, shifter, logical gates и т.п. на основной схеме не показываются.

Финальный набор операций:

```text
ADD
AND
XOR
INV
PASS
SHL
ASR
SRC
SLC
```

Для `ADD` используется:

```text
result = L + R + K
```

где:

```text
K in {0, +1, +5, -1}
```

---

## 7.1. Почему нет отдельных констант 1 и 5

Раньше `1` и `5` могли бы занимать отдельные входы MUX.

Это не требуется: они встроены в арифметическую функцию ALU как `K`.

Примеры:

```text
PC + 5
A + 1
R - 1
L + R
L + R + 1
```

---

## 7.2. AND

Побитовое:

```text
L & R
```

Используется напрямую командой `and`.

---

## 7.3. XOR

Побитовое:

```text
L ^ R
```

Аппаратный XOR оставлен, потому что это самостоятельная инструкция ISA. Раскладывать его на несколько микротактов через AND/INV не имеет смысла.

---

## 7.4. INV

```text
~X
```

Используется командой `inv`, а также может участвовать в реализации вычитания:

```text
X - Y = X + (~Y) + 1
```

Поэтому отдельный аппаратный `SUB` не обязателен.

---

## 7.5. PASS

`PASS` проводит выбранное значение через ALU без изменения.

Он удобен для простых пересылок через общую Data Bus:

```text
register -> ALU -> Data Bus -> destination register
```

---

## 7.6. SHL

Сдвиг влево на один бит.

Для обычного left shift освобождённый младший бит получает `0`.

---

## 7.7. ASR

Arithmetic Shift Right.

Используется для `2/`:

```text
x31 сохраняется как sign bit
```

---

## 7.8. SRC — Shift Right through Carry

Это не обычный rotate.

Состояние до:

```text
C | x31 x30 ... x1 x0
```

После SRC:

```text
C' = old x0
x31' = old C
```

То есть:

```text
old X[0] -> Carry
old Carry -> X[31]
```

Полезно для `+*`, где бит из T нужно перенести в старший бит A.

---

## 7.9. SLC — Shift Left through Carry

Аналогично:

```text
old X[31] -> Carry
old Carry -> X[0]
```

Полезно для `+/`, где старший бит A удобно переносить в младший бит S.

---

<a id="sec-8"></a>
# 8. Carry и EAM

## 8.1. Carry

Carry — 1-битное состояние.

Связи должны концептуально различаться:

```text
ALU -> Carry                  carry-out
Carry -> ALU_STATE_MUX -> ALU
EAM   -> ALU_STATE_MUX -> ALU
```

В текущей версии схемы `Carry` не подаётся напрямую в `Next Microcommand Logic`; при необходимости он используется ALU через третий входной MUX.

Запись:

```text
latch_c
```

Для `+`:

```text
EAM = 0: S + T
EAM = 1: S + T + Carry
```

После сложения Carry получает новое значение carry-out.

В F32A большинство инструкций очищает Carry; `+` формирует новый Carry, а `dup` сохраняет текущий. Это поведение должно обеспечиваться соответствующими микропрограммами.

---

## 8.2. EAM

EAM — Extended Arithmetic Mode, 1-битное состояние.

Запись:

```text
latch_e
```

Команда:

```text
eam
```

снимает значение с Data Stack и устанавливает EAM.

EAM поступает в `ALU_STATE_MUX` и далее в ALU как 1-битное состояние, а не как обычный 32-битный операнд. В текущей версии схемы EAM не является отдельным входом `Next Microcommand Logic`.

---

<a id="sec-9"></a>
# 9. Control Unit

Используется микропрограммное управление.

На схеме CU намеренно показан достаточно компактно:

```text
                IR/opcode
                    |
                    v
         Next Microcommand Logic
                    |
                    v
                   MPC
                    |
                    v
            Microcode Memory
                    |
                    v
                   MPR
                    |
                    v
             Control Signals
```

Также в `Next Microcommand Logic` поступают только те condition/status сигналы datapath, которые действительно нужны для выбора следующей микрокоманды. `Carry` и `EAM` в эту группу больше не входят: они маршрутизируются через `ALU_STATE_MUX` непосредственно в ALU.

---

## 9.1. MPC

`MPC` — Microprogram Counter / указатель микрокоманды.

Он содержит адрес микрокоманды в `Microcode Memory`.

Следующий MPC может концептуально определяться как:

```text
MPC + 1
branch target
dispatch(IR.opcode)
fetch entry
```

Точная комбинационная реализация этого выбора внутрь RTL-схемы не вынесена.

---

## 9.2. Microcode Memory

Память микрокоманд.

```text
address = MPC
data    = microinstruction
```

Каждая машинная инструкция F32A реализуется последовательностью микрокоманд.

---

## 9.3. MPR

`MPR` — Microprogram/Microcommand Register в принятой схеме.

Он хранит текущую 40-битную микроинструкцию.

Из него:

- формируются управляющие сигналы datapath;
- часть полей возвращается в `Next Microcommand Logic`.

---

## 9.4. Next Microcommand Logic

Этот блок абстрагирует:

- последовательный переход `MPC + 1`;
- dispatch по opcode из IR;
- безусловный переход внутри микропрограммы;
- условный переход;
- возврат к fetch;
- остановку.

Внутренние `+1`, decoder, branch gates и т.п. отдельно не рисуются.

---

## 9.5. Conditions

Для сложных микропрограмм CU может использовать condition-сигналы, необходимые для ветвления микропрограммы, например:

```text
A[0]
A[31]
T[0]
T == 0
T sign
R != 0
```

`Carry` и `EAM` здесь намеренно отсутствуют: в актуальной схеме они идут через третий MUX в ALU, а не в `Next Microcommand Logic`.

Эти проверки относятся к condition path Control Unit.

Отдельные логические элементы/компараторы на основной RTL-схеме не показываются.

---

<a id="sec-10"></a>
# 10. Формат микроинструкции

Принята фиксированная ширина:

```text
40 bits
```

Структура:

```text
+-----------------------------+----------------------+
| Datapath control — 30 bits  | Next control — 10   |
+-----------------------------+----------------------+
```

30-битная операционная часть определена подробно.

10-битная часть зарезервирована для управления последовательностью микрокоманд (`Next Microcommand Logic`). Точное внутреннее кодирование этой части на RTL-схеме не детализируется.

---

<a id="sec-11"></a>
# 11. Управляющие сигналы datapath

## 11.1. Latch signals — 11 bits

Каждый сигнал разрешает запись соответствующего регистра:

| Сигнал | Бит |
|---|---:|
| `latch_mar` | 1 |
| `latch_ir` | 1 |
| `latch_mdr` | 1 |
| `latch_a` | 1 |
| `latch_b` | 1 |
| `latch_t` | 1 |
| `latch_s` | 1 |
| `latch_r` | 1 |
| `latch_pc` | 1 |
| `latch_c` | 1 |
| `latch_e` | 1 |

Итого:

```text
11 bits
```

---

## 11.2. MUX selects — 7 bits

```text
sel_lf : 2 bits
sel_rt : 2 bits
sel_s  : 1 bit
sel_r  : 1 bit
sel_ce : 1 bit
```

`sel_ce` управляет третьим MUX ALU и выбирает, какое 1-битное состояние поступает в ALU: `Carry` или `EAM`.

Итого:

```text
7 bits
```

Пример кодирования ALU MUX:

```text
sel_lf:
00 S
01 A
10 R
11 PC

sel_rt:
00 0
01 T
10 B
11 MDR

sel_ce:
0 Carry
1 EAM
```

Кодирование `sel_s` и `sel_r` зависит только от порядка двух входов соответствующих MUX.

---

## 11.3. ALU operation — 4 bits

Всего выделено:

```text
alu_op : 4 bits
```

Один удобный вариант кодирования:

```text
0000 ADD, K = 0
0001 ADD, K = +1
0010 ADD, K = +5
0011 ADD, K = -1

0100 AND
0101 XOR
0110 INV
0111 PASS

1000 SHL
1001 ASR
1010 SRC
1011 SLC

1100 reserved
1101 reserved
1110 reserved
1111 reserved
```

Таким образом четыре кода остаются свободными для расширения.

---

## 11.4. Stack operations — 4 bits

```text
op_dsp : 2 bits
op_rsp : 2 bits
```

Рекомендуемое кодирование:

```text
00 HOLD
01 PUSH / INC
10 POP  / DEC
11 RESERVED
```

Итого:

```text
4 bits
```

---

## 11.5. Memory control — 2 bits

```text
mem_re : 1
mem_we : 1
```

Итого:

```text
2 bits
```

---

## 11.6. Data Bus output enable — 2 bits

```text
alu_oe : 1
rd_oe  : 1
```

Итого:

```text
2 bits
```

---

## 11.7. Общая ширина операционной части

```text
latch_*          11
MUX selects       7
alu_op            4
op_dsp/op_rsp     4
mem_re/mem_we     2
alu_oe/rd_oe      2
-------------------
TOTAL             30 bits
```

Полная микроинструкция:

```text
30 + 10 = 40 bits
```

---

<a id="sec-12"></a>
# 12. Fetch машинной инструкции

Размер машинной инструкции F32A:

```text
opcode        1 byte
each argument 4 bytes
```

Поэтому инструкция без operand занимает 1 байт, а с одним operand — 5 байт.

Конкретные микротакты могут быть реализованы по-разному; принцип:

### Opcode fetch

```text
MAR <- PC
mem_re
IR <- memory[MAR]
update PC / dispatch
```

### Operand fetch

Если opcode требует 4-байтовый argument:

```text
MAR <- operand address
mem_re
MDR <- memory[MAR]
PC <- next instruction address
```

`MDR` позволяет сохранить operand и не требовать немедленного использования результата RAM в том же микротакте.

---

<a id="sec-13"></a>
# 13. Как исполняются основные группы инструкций

Ниже не фиксируется единственно возможный микрокод. Цель — показать, что datapath физически способен выполнить ISA.

---

## 13.1. Memory instructions

### `@`

```text
A -> MAR
mem_re
RAM -> RD_MUX -> Data Bus -> push Data Stack
```

### `@+`

То же самое, затем:

```text
A <- A + 1
```

### `@b`

```text
B -> ALU/PASS -> MAR
mem_re
memory -> Data Stack
```

### `!`

```text
A -> MAR
T -> ALU/PASS -> Data Bus
mem_we
pop Data Stack
```

### `!+`

То же плюс:

```text
A <- A + 1
```

### `@p`, `!p`

Адрес команды сначала читается как operand и сохраняется в MDR, после чего может быть передан в MAR.

---

<a id="sec-14"></a>
# 14. Простая арифметика

## `+`

```text
L = S
R = T
ALU = ADD
```

Если EAM выключен:

```text
T <- S + T
```

Если EAM включён:

```text
T <- S + T + Carry
```

После операции новое значение Carry формируется ALU.

---

## `and`

```text
T <- S AND T
pop one operand
```

---

## `xor`

```text
T <- S XOR T
pop one operand
```

---

## `inv`

```text
T <- INV(T)
```

---

## `2*`

```text
T <- SHL(T)
```

---

## `2/`

```text
T <- ASR(T)
```

---

<a id="sec-15"></a>
# 15. Multiply Step `+*`

Семантика F32A:

```text
T <- T + (A[0] ? S : 0)
A <- A >> 1
A[31] <- T[0]
T <- T >> 1
```

Удобная реализация:

1. CU проверяет `A[0]`.
2. Если `A[0] = 1`, выполнить:

```text
T <- T + S
```

3. Сдвинуть T вправо, передав вытолкнутый `T[0]` в Carry.
4. Выполнить `SRC` для A: старый Carry попадает в `A[31]`.

Тем самым Carry используется как однобитный мост:

```text
T[0] -> Carry -> A[31]
```

Отдельные маски, OR и специальные `SET_BIT` операции не нужны.

---

<a id="sec-16"></a>
# 16. Divide Step `+/`

Семантика:

```text
dividend          = A
divisor           = mem[B]
partial remainder = S
partial quotient  = T
```

Шаг:

```text
S <- S << 1
S[0] <- old A[31]
A <- A << 1
T <- T << 1

if S >= divisor:
    S <- S - divisor
    T[0] <- 1
```

Микроархитектурно:

1. `B -> MAR`
2. `mem[B] -> MDR`
3. сдвиг A влево, вынесенный `A[31]` сохранить в Carry;
4. `SLC(S)` — выполнить `S << 1` и вставить Carry в `S[0]`;
5. выполнить сдвиг T влево;
6. сравнить S с делителем;
7. при необходимости выполнить вычитание.

Вычитание можно выполнить без отдельного `SUB`:

```text
S - MDR = S + INV(MDR) + 1
```

Если после сравнения нужно установить младший бит quotient, `SLC`/арифметика с `+1` позволяют сделать это без отдельной аппаратной `SET_BIT`.

---

<a id="sec-17"></a>
# 17. Stack instructions

## `drop`

Уменьшить Data Stack depth.

Stack subsystem сам выполняет необходимый fill:

```text
S -> T
DS_MEM -> S        if required
```

---

## `dup`

Дублировать T:

```text
push(T)
```

Особенность ISA: `dup` сохраняет Carry.

---

## `over`

Состояние:

```text
... S T
```

должно стать:

```text
... S T S
```

При необходимости MDR может использоваться как временное хранилище на нескольких микротактах.

---

## `r>`

```text
R -> Data Stack
pop Return Stack
```

---

## `>r`

```text
T -> Return Stack
pop Data Stack
```

---

<a id="sec-18"></a>
# 18. Control-flow instructions

## `;` — return

```text
PC <- R
pop Return Stack
```

---

## Call `<label>`

```text
push return address to Return Stack
PC <- label
```

Operand target может быть прочитан в MDR.

---

## Jump `<label> ;`

```text
PC <- target
```

без push Return Stack.

---

## `if <label>`

Условие:

```text
T == 0
```

T снимается со стека независимо от результата.

Если условие истинно:

```text
PC <- target
```

---

## `-if <label>`

Условие:

```text
T >= 0
```

То есть для 32-битного signed значения достаточно учитывать sign condition.

---

## `next <label>`

```text
if R != 0:
    R <- R - 1
    PC <- label
else:
    pop Return Stack
```

Именно ради `R - 1` удобно иметь:

```text
K = -1
```

в ADD ALU.

---

## `halt`

Control Unit прекращает продвижение микропрограммы/машинных инструкций.

Нового datapath-блока не требуется.

---

<a id="sec-19"></a>
# 19. Почему архитектура считается функционально полной

Datapath был проверен по всем группам F32A ISA:

- immediate/data movement;
- RAM/MMIO;
- A/B operations;
- stack operations;
- arithmetic;
- bitwise operations;
- shifts;
- EAM/Carry через `ALU_STATE_MUX`;
- multiply step;
- divide step;
- return stack;
- call/jump/if/-if/next/halt.

Критические места, для которых были введены отдельные решения:

```text
MDR     — удержание memory operand/divisor/literal
SRC     — перенос T[0] -> Carry -> A[31] в +*
SLC     — перенос A[31] -> Carry -> S[0] в +/
K=-1    — удобное R := R - 1 для next
alu_oe  — разрешение ALU управлять Data Bus
rd_oe   — разрешение memory path управлять Data Bus
```

После этих решений отдельная инструкция F32A не требует принципиально нового datapath-блока.

---

<a id="sec-20"></a>
# 20. Что является внутренней реализацией и не рисуется

На основной RTL-схеме намеренно **не показываются**:

- логические вентили AND/OR внутри блоков;
- отдельные компараторы `A[0]`, `T==0` и т.п.;
- внутренний сумматор `DSP/RSP`;
- вычисление backing-memory index;
- stack `re/we` logic;
- внутренний shifter ALU;
- `MPC + 1` adder;
- opcode decoder как отдельная схема;
- branch gates Control Unit;
- тактовый генератор и разводка `CLK` ко всем регистрам.

Это считается внутренней реализацией соответствующих RTL-блоков.

Все регистры синхронизируются общим тактовым сигналом; `latch_*` являются разрешениями записи.

---

<a id="sec-21"></a>
# 21. Что важно уметь объяснить на защите

### Почему T/S/R — регистры, если F32A стековая?

Они не являются дополнительными архитектурными general-purpose registers. Это микроархитектурный кэш верхних элементов стеков:

```text
T = top Data Stack
S = second Data Stack
R = top Return Stack
```

Остальные элементы хранятся в backing memory.

### Почему DSP/RSP — depth, а не адрес?

Потому что первые элементы стеков кэшируются вне памяти. Реальный backing-memory index зависит от глубины и конкретной операции. Эту логику удобнее скрыть внутри Stack Segment.

### Зачем MDR?

Чтобы отвязать момент чтения RAM от момента использования значения: operand, literal или `mem[B]` можно прочитать один раз и держать несколько микротактов.

### Почему нет SUB?

```text
X - Y = X + (~Y) + 1
```

ALU уже имеет `INV` и `ADD + K`.

### Почему нет OR?

Он не нужен как базовая инструкция ISA и при редкой необходимости может быть синтезирован:

```text
X OR Y = ~(~X AND ~Y)
```

### Зачем SRC/SLC?

Для переноса одного бита между регистрами через Carry без масок и специальных операций `SET_BIT`. Сам `Carry` поступает в ALU через `ALU_STATE_MUX`.

### Зачем alu_oe и rd_oe?

Потому что ALU и memory path являются двумя драйверами одной Data Bus. Значение `0` не означает отключение выхода; нужен Output Enable.

### Почему память декодируется по MAR?

Memory-mapped I/O использует то же адресное пространство. Address Decoder определяет, адрес относится к RAM, input или output.

### Почему Microcode Memory отдельная?

Это память управляющих микрокоманд, а не машинных инструкций. Машинный opcode определяет микропрограмму, а её микрокоманды уже формируют управляющие сигналы datapath.

### Почему 40 бит?

30 бит требуются известным управляющим сигналам datapath, включая `sel_ce` третьего MUX ALU. Ещё 10 бит отведены под управление последовательностью микрокоманд. Такая ширина достаточна для выбранной реализации и оставляет структуру CU простой.

---

<a id="sec-22"></a>
# 22. Краткая шпаргалка по всей схеме

```text
MACHINE INSTRUCTION
RAM -> IR -> Control Unit

CONTROL UNIT
IR/status/MPR -> Next Microcommand Logic
              -> MPC
              -> Microcode Memory
              -> MPR
              -> control signals

MEMORY
Data Bus -> MAR
MAR -> RAM + Address Decoder
Address Decoder + mem_re/mem_we -> RAM/MMIO selection
RAM/MM_IN -> RD_MUX -> Data Bus
Data Bus -> RAM/MM_OUT

ALU
S/A/R/PC -> ALU_L_MUX ----\
0/T/B/MDR -> ALU_R_MUX ----+-> ALU -> Data Bus
Carry/EAM -> ALU_STATE_MUX -/

STACKS
T,S + DS_MEM + DSP
R   + RS_MEM + RSP
op_dsp/op_rsp = HOLD/PUSH/POP

BUS
ALU -> [alu_oe] -> Data Bus
RD_MUX -> [rd_oe] -> Data Bus

MICROINSTRUCTION
40 bits = 30 datapath + 10 next-control
```

---

<a id="sec-23"></a>
# 23. Источники

Основная документация F32A:

- https://github.com/ryukzak/wrench/blob/master/docs/f32a.md

Wrench:

- https://github.com/ryukzak/wrench

Исходная реализация F32A в Wrench:

- https://github.com/ryukzak/wrench/blob/master/src/wrench/Wrench/Isa/F32a.hs

При расхождении между этим README и официальной семантикой ISA источником истины по поведению инструкций является актуальная документация/реализация Wrench. Микроархитектурные детали этого README описывают конкретную разработанную RTL-схему и не претендуют на единственную возможную реализацию F32A.
