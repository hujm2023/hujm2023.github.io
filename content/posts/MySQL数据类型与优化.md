---
title: MySQL数据类型与优化
author: JemmyHu(hujm20151021@gmail.com)
toc: true
mathjax: false
summary:
categories: [技术博客, 技术细节, MySQL]
tags: [MySQL, MySQL数据类型]
comment: true
date: 2020-09-14 01:37:04
cover:
  image: https://i0.wp.com/blog.toright.com/wp-content/uploads/2016/09/MySQL-Logo.png?fit=213%2C188&ssl=1
---

## 选择优化的数据类型

`MySQL` 支持多种数据类型，但是每个类型都有自己适合的场景，选对类型对性能的提高至关重要。以下原则仅供参考：

- **更小的通常更好**

  一般情况下，应该尽量选择可以存储数据的最小数据类型。如只需要存 `0 ~ 200` ，那么字段类型设置为 `unsigned tinyint` 更好。

- **简单就好**

  简单数据类型的操作通常需要更少的 CPU 周期。例如整形比字符串的操作代价更低，因为字符串还要考虑 **字符集** 和 **排序规则** ，使得字符串的比较比整形更加复杂。这里有两个例子：存储日期时，应该使用 `MySQL` 的内建类型( `date` 、 `time` 、 `datetime` 、 `timestamp` 等)而不是使用字符串；存储 **IP** 地址时，应该使用整型而非字符串， `MySQL` 中有专门的处理函数：

```mysql
    mysql> select INET_ATON("172.16.11.102");
    +----------------------------+
    | INET_ATON("172.16.11.102") |
    +----------------------------+
    |                 2886732646 |
    +----------------------------+

    mysql> select INET_NTOA(2886732646);
    +-----------------------+
    | INET_NTOA(2886732646) |
    +-----------------------+
    | 172.16.11.102         |
    +-----------------------+
```

- **行属性尽量避免 NULL**

  一般情况下，某一行的默认属性是 `NULL` 。书中(《高性能 MySQL》)建议，最好指定列为 `NOT NULL` ，除非真的需要存储 `NULL` 值。这只是一个建议——如果计划在列上建索引，应该尽量避免设计成 可为 `NULL` 的列。

## 1. 数字

### 1.1 整型(Whole Number)

可使用类型如下：

|      类型       |      位数       |                                   范围                                   |
| :-------------: | :-------------: | :----------------------------------------------------------------------: |
|  **`TINYINT`**  | 8 位（1 字节）  |                                 -128~127                                 |
| **`SMALLINT`**  | 16 位（2 字节） |                               -32768~32767                               |
| **`MEDIUMINT`** | 24 位（3 字节） |                       -8388608~8388607（830 万多）                       |
|    **`INT`**    | 32 位（4 字节） |                    -2147483648~2147483647（21 亿多）                     |
|  **`BIGINT`**   | 64 位（8 字节） | -9223372036854775808~922, 3372, 0368, 5477, 5807（900 亿亿，反正很大啦） |

整型有可选的 `unsigned` ，表示 **非负** ，这大致可使正数的上限提高一倍。

**有符号和无符号整数使用相同的存储空间，有相同的性能，可根据实际情况选择以适合自己业务。**

`MySQL` 可以为整数类型指定宽度，例如 **`INT(11)`**， 但绝大多数情况下**没有意义**：对于存储和计算来说，**`INT(11)`**和 **`INT(20)`**是相同的，**宽度不会限制值的合法范围**，只是规定了 `MySQL` 的一些交互工具用来显示字符的个数。

### 1.2 实数类型(Real Number)

**实数是指 带有小部分的数字**。我们能接触到的有 `FLOAT` 、 `DOUBLE` 和 `DECIMAL` 。这三个可以进一步划分： `FLOAT` 、 `DOUBLE` 称为浮点型， `DECIMAL` 就是 DECIMAL 类型。

我们知道，标准的浮点运算由于硬件原因（篇幅所限具体原因请自行寻找），进行的是近似运算，如 `Python 3.8` 中 $0.1 + 0.2 = 0.30000000000000004$， `Golang go1.13.4 darwin/amd64` 中 `fmt.Println(fmt.Sprintf("%0.20f", 0.1+0.2))` 输出$0.29999999999999998890 $ ，而 `FLOAT` 和 `DOUBLE` 所属的 **浮点型** 进行的就是这种运算。

而 **DECIMAL 用于存储精确的小数**。因为 `CPU` 不支持对 `DECIMAL` 的直接计算，因此 **在 `MySQL 5.0及以后的版本` 中， `MySQL` 服务器自身实现了 `DECIMAL` 的高精度计算**。因此我们可以说，后期版本中，**MySQL 既支持精确类型，也支持不精确类型。** 相对而言， `CUP` 直接支持原生浮点运算，所以浮点运算明显更快。

> `MySQL` 使用二进制的形式存储 `DECIMAL` 类型。使用方式为 `DECIMAL(总位数，小数点后位数)` ，其中总位数最大为 65，小数点后位数最大为 30；并且位数与字节大小的对应关系为 `9位/4字节` ，即每 9 位占 4 个字节，同时小数点占用一个字节。比如 DECIMAL(20, 9)共占用 5 个字节——小数点左边占用 3 个字节，小数点一个字节，小数点右边共占一个字节。

**浮点类型**在存储同样范围的值时，通常比 **`DECIMAL`**使用更少的空间。 `FLOAT` 使用 4 个字节存储， `DOUBLE` 占用 8 个字节。**需要注意的是，我们能选择的只是类型，即表示的范围大小，和整形一样，在 `MySQL` 底层进行计算的时候，所有的实数进行计算时都会转换成 `DOUBLE` 类型**。

## 2. 字符串

### 2.1 VARCHAR(变长字符串)

`VARCHAR` 用于存储可变长字符串，是最常见的字符串数据类型。它比**定长类型(CHAR)**更加**节省空间，因为它仅使用必要的空间**。

**变长字符串 `VARCHAR` 需要使用额外的 1 个或 2 个字节记录字符串的长度：如果列的最大长度<=255 字节，则使用 1 个字节表示，否则使用 2 个字节。**

`VARCHAR` 节省空间，这对性能提升也有帮助，但由于行长是变的，如果通过 `UPDATE` 操作使得行长变得比原来更长，那就需要做一些额外的工作。不同引擎有不同的处理结果。

> 当 VARCHAR 过长时，InnerDB 会将其保存为 BLOB，同时使用专门的外部区域来保存大文件，行中只保存对应的地址。

### 2.2 CHAR(定长字符串)

当使用 `CHAR(n)` 时，会一次性分配足够的空间，注意这里的 `n` 指的是字符数而不是字节数。**当存储 `CHAR` 时，会自动去掉末尾的空格，而 `VARCHAR` 不会**。

`CHAR` 非常适合存储很短的字符串，或者长度都很接近的字符串，例如密码的 MD5 值，因为这是一个定长的值。对于非常短的列， `CHAR` 比 `VARCHAR` 在存储空间上更有效率。

> 关于“末尾空格截断”，通过下面的例子说明：

````mysq
>   mysql> CREATE TABLE t1 (cl CHAR(10));
>   mysql> INSERT INTO t1(cl) VALUES('string1'),('   string2'),('string3  ');
>   # 执行查询
>   mysql> SELECT CONCAT("'",cl,"'") FROM t1;
>   +--------------------+
>   | CONCAT("'",cl,"'") |
>   +--------------------+
>   | 'string1'          |
>   | '   string2'       |
>   | 'string3'          |
>   +--------------------+
>   ```

>
> 我们再看下VARCHAR：
>
>

``` mysq
>   mysql> CREATE TABLE t2 (cl VARCHAR(10));
>   mysql> INSERT INTO t2(cl) VALUES('string1'),('   string2'),('string3  ');
>   # 执行查询
>   mysql> SELECT CONCAT("'",cl,"'") FROM t2;
>   +--------------------+
>   | CONCAT("'",cl,"'") |
>   +--------------------+
>   | 'string1'          |
>   | '   string2'       |
>   | 'string3  '        |
>   +--------------------+
````

区别主要在 `string3` 后面的空格是否被截断。

### 2.3 BLOB 和 TEXT

`BLOB` 和 `TEXT` 都是为存储很大的数据而设计的字符串数据类型，分别采用**二进制**和**字符**方式存储。

它们属于不同的数据类型：字符类型有 TINYTEXT, SMQLLTEXT, TEXT, MEDIUMTEXT, LONGTEXT，对应的二进制类型有 TINYBLOB, SMQLLBLOB, BLOB, MEDIUMBLOB, LONGBLOB。其中 **BLOB 是 SMALLBLOB 的同义词，TEXT 是 SMALLTEXT 的同义词**。

**当 BLOB 和 TEXT 的值太大时，InnerDB 会使用专门的“外部存储区域”进行存储实际内容，而行内使用 1~4 个字节存储一个外部内容的指针**。

BLOB 和 TEXT 家族之间仅有的不同是：BLOB 存储的是二进制的数据，没有排序规则和字符集，而 TEXT 有字符集和排序规则。

`MySQL` 对 BLOB 和 TEXT 进行排序时与其他类型是不同的：它只针对没个列的最前 `max_sort_length` 字节而不是对整个字符串进行排序。如果需要排序的字符更少，可以尝试减小 `max_sort_length` ，或者使用 `ORDER BY SUSTRING(column,length)` 。

**MySQL 不能将 BLOB 或者 TEXT 列全部长度的字符串作为索引！**

## 3. 枚举、集合和位

### 3.1 枚举(ENUM)

枚举可以将一些不重复的字符串放到一个预定义的集合中，使用时也只能插入这个预定义集合中的**某一个**。

**MySQL 在存储枚举值时非常紧凑，在内部保存时，会将每个值在列表中的位置保存为整数(从 1 开始编号)，并在表的.frm 文件中保存“数字-字符串”映射关系的“查找表”；数据保存在两个字节中，因此枚举中可以有 $2^{16} - 1 = 65535$个**。

```mysql
mysql> CREATE TABLE t2(e ENUM('fish','apple','dog'));
mysql> INSERT INTO t2(e) VALUES('fish'),('dog'),('apple'),(1); # 注意，这里也可以世界使用枚举值对应的位置，如1对应'apple'
# 查询枚举值，默认字符串表示
mysql> SELECT * FROM t2;
+-------+
| e     |
+-------+
| fish  |
| dog   |
| apple |
| fish  |
+-------+
# 使用数字形式表示枚举值
mysql> SELECT e+0 FROM t2;
+------+
| e+0  |
+------+
|    1 |
|    3 |
|    2 |
|    1 |
+------+
```

**尽量不要使用数字作为 ENUM 枚举常量，这种双重性很容易导致混乱，例如 `ENUM('1','2','3')` 。**

**注意：枚举字段是按照内部存储的整数而不是字符串顺序进行排序的。**一种绕过这种限制的方式是 **刚开始就按照字典顺序来定义枚举值**，另一中方式是使用 `FIELD(列名，'arg1','arg2',…)` 函数：

```mysq
mysql> SELECT e FROM t2 ORDER BY FIELD(e,'apple','dog','fish');
+-------+
| e     |
+-------+
| apple |
| dog   |
| fish  |
| fish  |
+-------+
```

### 3.2 集合(SET)

如果说 `ENUM` 是单选的话，那 `SET` 就是多选。适合存储预定义集合中的多个值。同 `ENUM` 一样，其底层依旧通过整形存储。

设定 set 的格式：

```mysql
字段名称 SET("选项1","选项2",...,'选项n')
如
CREATE TABLE t3(hobby SET('swim','music','movie','football'));
```

同样的， `SET` 的每个选项值也对应一个数字，依次是 `1，2，4，8，16...，` 最多有 64 个选项。

使用的时候，可以使用 set 选项的字符串本身（多个选项用逗号分隔），也可以使用多个选项的数字之和（比如：1+2+4=7）。

通过实例来说明：

```mysql
# 建表
CREATE TABLE t3(hobby SET('swim','music','movie','football'));
# 插入一个选项，字符串格式
INSERT INTO t3(hobby) VALUES('swim');
# 插入多个选项，字符串格式，通过英文逗号分隔
INSERT INTO t3(hobby) VALUES('swim,movie');
# 插入一个选项，数字格式
INSERT INTO t3(hobby) VALUES(1); # 等同于'swim'
INSERT INTO t3(hobby) VALUES(4); # 等同于'movie'
# 插入多个选项，数字格式
INSERT INTO t3(hobby) VALUES(7); # 等同于'swim,music,movie'，因为'swim','music','movie','football'分别为“1,2,4,8”，7=1+2+4.

# 显示全部
mysql> SELECT * FROM t3;
+------------------+
| hobby            |
+------------------+
| swim             |
| swim,movie       |
| swim             |
| movie            |
| swim,music,movie |
+------------------+

# 查找包含movie的行
mysql> SELECT * FROM t3 WHERE FIND_IN_SET('movie',hobby) > 0;
+------------------+
| hobby            |
+------------------+
| swim,movie       |
| movie            |
| swim,music,movie |
+------------------+
# 寻找包含排号为4的成员的行
mysql> SELECT * FROM t3 WHERE hobby & 4;
+------------------+
| hobby            |
+------------------+
| swim,movie       |
| movie            |
| swim,music,movie |
+------------------+
# 直接使用字符串匹配
mysql> SELECT * FROM t3 WHERE hobby = 'swim,movie';
+------------+
| hobby      |
+------------+
| swim,movie |
+------------+
```

### 3.3 位(BIT)

`NySQL` 把 `BIT` 当成字符串类型而不是数字类型来存储。但是它的存储结果根据上下文会出现不同：

```mysql
mysql> CREATE TABLE t4(a BIT(8));
mysql> INSERT INTO t4(a) VALUES(b'00111001');
mysql> SELECT a, a+0 ,BIN(a) FROM t4; # bin()表示整数类型对应的二进制
+------+------+--------+
| a    | a+0  | BIN(a) |
+------+------+--------+
| 9    |   57 | 111001 |
+------+------+--------+
```

默认显示数字代表的 `ASCII` 码字符。
