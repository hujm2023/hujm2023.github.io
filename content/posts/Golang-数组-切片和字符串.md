---
title: "Golang-数组,切片和字符串"
author: JemmyHu(hujm20151021@gmail.com)
toc: true
mathjax: true
summary:
categories: [技术博客, 技术细节, Golang]
tags: [Golang, 数组, 切片, 字符串]
comment: true
date: 2020-09-16 02:15:54
cover:
  image: https://pic.downk.cc/item/5f5fa4a5160a154a67fdbc36.png
---

在主流的编程语言中数组及其相关的数据结构是使用得最为频繁的，只有在它(们)不能满足时才会考虑链表、hash 表（hash 表可以看作是数组和链表的混合体）和更复杂的自定义数据结构。

Go 语言中数组、字符串和切片三者是密切相关的数据结构。这三种数据类型，在底层原始数据有着相同的内存结构，在上层，因为语法的限制而有着不同的行为表现。

## 一、 数组(Array)

### 1. 概述

数组是由相同类型元素的集合组成的数据结构，计算机会为数组分配一块连续的内存来保存其中的元素，我们可以利用数组中元素的索引快速访问元素对应的存储地址。

数组作为一种基本的数据类型，我们通常都会从两个维度描述数组：类型 和 大小(能够存储的最大元素个数)：

```go
// 源码位于 /usr/local/go/src/cmd/compile/internal/types/type.go
// Array contains Type fields specific to array types.
type Array struct {
 Elem  *Type // element type 元素类型
 Bound int64 // number of elements; <0 if unknown yet 最大元素个数，小于0表示未知
}

// NewArray returns a new fixed-length array Type.
func NewArray(elem *Type, bound int64) *Type {
 if bound < 0 {
  Fatalf("NewArray: invalid bound %v", bound)
 }
 t := New(TARRAY)
 t.Extra = &Array{Elem: elem, Bound: bound}
 t.SetNotInHeap(elem.NotInHeap())
 return t
}
```

从上述代码可以看出，类型`Array`包含两个属性，一个是数组类型`Elem`，另一个是数组大小`Bound`。另外需要注意的是：**Go 语言中数组在初始化之后大小无法改变**。

### 2. 初始化

有两种初始化方式：

```go
array1 = [5]int{1, 2, 3, 4, 5}
array2 = [...]int{1, 2, 3, 4, 5}
```

上述两种声明方式在运行期间得到的结果是完全相同的，后一种声明方式在编译期间就会被“转换”成为前一种，这也就是编译器对数组大小的推导。

对第一种方式，那么变量的类型在编译进行到**类型检查**阶段就会被提取出来，随后会使用 `NewArray`函数创建包含数组大小的 `Array` 类型。

对第二种方式，在第一步会创建一个`Array{Elem: elem, Bound: -1}`，即其大小会是`-1`，不过这里的`-1`只是一个占位符，编译器会在后面的 `/usr/local/go/src/cmd/compile/internal/gc/typecheck.go` 中对数组大小进行推导，并更新其 `Bound` 值：

```go
// The result of typecheckcomplit MUST be assigned back to n, e.g.
//  n.Left = typecheckcomplit(n.Left)
func typecheckcomplit(n *Node) (res *Node) {
    ...
     // Need to handle [...]T arrays specially.
 if n.Right.Op == OTARRAY && n.Right.Left != nil && n.Right.Left.Op == ODDD {
  n.Right.Right = typecheck(n.Right.Right, ctxType)
  if n.Right.Right.Type == nil {
   n.Type = nil
   return n
  }
  elemType := n.Right.Right.Type

        // typecheckarraylit type-checks a sequence of slice/array literal elements.
  length := typecheckarraylit(elemType, -1, n.List.Slice(), "array literal")

  n.Op = OARRAYLIT
  n.Type = types.NewArray(elemType, length)
  n.Right = nil
  return n
 }
    ...
}

```

虽然在编译期这两种方式的实现方式不同，但在运行时这两中方式是完全等价的。事实上，`[...]T` 这种初始化方式也只是 Go 语言为我们提供的一种语法糖，当我们不想计算数组中的元素个数时可以偷个懒。

另：变量初始化的位置：

如果数组中元素的个数小于或者等于 4 个，那么所有的变量会直接在栈上初始化；如果数组元素大于 4 个，变量就会在静态存储区初始化然后拷贝到栈上，这些转换之后代码才会继续进入 **中间代码生成** 和 **机器码生成** 两个阶段，最后生成可以执行的二进制文件。

### 3. 赋值与访问

Go 语言中数组是值语义。一个数组变量即表示整个数组，它并不是隐式的指向第一个元素的指针（比如 C 语言的数组），而是一个完整的值。当一个数组变量被赋值或者被传递的时候，实际上会复制整个数组。如果数组较大的话，数组的赋值也会有较大的开销。为了避免复制数组带来的开销，可以传递一个指向数组的指针，但是数组指针并不是数组。

```go
var a = [...]int{1, 4, 3} // a 是一个数组
var b = &a                // b 是指向数组的指针

fmt.Println(a[0], a[1])   // 打印数组的前2个元素
fmt.Println(b[0], b[1])   // 通过数组指针访问数组元素的方式和数组类似

for i, v := range b {     // 通过数组指针迭代数组的元素
    fmt.Println(i, v)
}
```

我们可以用`for`循环来迭代数组。下面常见的几种方式都可以用来遍历数组：

```go
fmt.Println("方式一：")
for i := range a {
    fmt.Printf("a[%d]: %d\n", i, a[i])
}
fmt.Println("方式二：")
for i, v := range a {
    fmt.Printf("a[%d]: %d\n", i, v)
}
fmt.Println("方式三：")
for i := 0; i < len(a); i++ {
    fmt.Printf("a[%d]: %d\n", i, a[i])
}

// 输出
方式一：
a[0]: 1
a[1]: 4
a[2]: 3
方式二：
a[0]: 1
a[1]: 4
a[2]: 3
方式三：
a[0]: 1
a[1]: 4
a[2]: 3
```

用`for range`方式迭代的性能可能会更好一些，因为这种迭代可以保证不会出现数组越界的情形，每轮迭代对数组元素的访问时可以省去对下标越界的判断。

需要注意的是 **长度为 0 的数组**。**长度为 0 的数组在内存中并不占用空间**，有时候可以用于强调某种特有类型的操作时避免分配额外的内存空间，比如用于管道的同步操作：

```go
c1 := make(chan [0]int)
go func() {
    fmt.Println("c1")
    c1 <- [0]int{}
}()
<-c1
```

在此场景下我们并不关心管道中的具体数据以及类型，我们需要的只是管道的接收和发送操作用于消息的同步，此时，空数组作为管道类型可以减少管道元素赋值时的开销。当然一般更倾向于用无类型的匿名结构体代替：

```go
c2 := make(chan struct{})
go func() {
    fmt.Println("c2")
    c2 <- struct{}{} // struct{}部分是类型, {}表示对应的结构体值
}()
<-c2
```

注：本节参考自[Go 语言高级编程 1.4](https://chai2010.gitbooks.io/advanced-go-programming-book/content/ch1-basic/ch1-03-array-string-and-slice.html)

## 二、切片(Slice)

切片和数组非常类似，可以用下标的方式访问，也会在访问越界时发生`panic`。但它比数组更加灵活，可以自动扩容。

### 1. 内部实现

源代码位于： /usr/local/go/src/runtime/slice.go

```go
type slice struct {
 array unsafe.Pointer  // 指向底层数组的指针
    len   int             // 长度(已经存放了多少个元素)
    cap   int             // 容量(底层数组的元素个数)，其中 cap>=len
}
```

![slice底层结构](https://pic.downk.cc/item/5f5f9e28160a154a67fc3734.png)

需要注意的是，底层的数组是可以被多个 slice 同时指向的，因此，对一个 slice 元素进行操作可能会影响其他指向对应数组的 slice。

![底层的数组是可以被多个slice同时指向](https://pic.downk.cc/item/5f5fa4a5160a154a67fdbc36.png)

### 2. slice 的创建

|        方式        | 代码示例                | 说明                                                                                                                    |
| :----------------: | :---------------------- | :---------------------------------------------------------------------------------------------------------------------- |
|      直接声明      | var arr1 []int          | 其实是一个`nil slice`，`array=nil,len=0,cap=0`。此时没有开辟内存作为底层数组。                                          |
|        new         | arr2 := \*new([]int)    | 也是一个`nil slice`，没有开辟内存作为底层数组。也没有设置元素容量的地方，此时只能通过`append`来添加元素，不能使用下标。 |
|       字面量       | arr3 := []int{1,2,3}    |                                                                                                                         |
|        make        | arr4 := make([]int,2,5) | 切片类型、长度、容量，其中容量可以不传，默认等于长度。                                                                  |
| 从切片或数组“截取” | arr5 := arr4[1:2]       |                                                                                                                         |

### 3. 关于 make 创建 slice

Go 编译器会在编译期，根据以下两个条件来判断在哪个位置创建 slice：

1. 切片的大小和容量是否足够小
2. 切片是否发生了逃逸

当**要创建的切片非常小并且不会发生逃逸**时，这部分操作会在编译期完成，并且创建在栈上或者静态存储区。如 `n := make([]int,3,4)` 会被直接转化成如下所示的代码：

```go
var arr = [4]int
n := arr[:3]
```

当发生逃逸或者比较大时，会在运行时调用 `runtime.makeslice` 函数在堆上初始化。而`runtime.makeslice`函数非常简单：

```go
// et是元素类型
func makeslice(et *_type, len, cap int) unsafe.Pointer {
 mem, overflow := math.MulUintptr(et.size, uintptr(cap))
    // 判断len cap参数是否合法
 if overflow || mem > maxAlloc || len < 0 || len > cap {
  // NOTE: Produce a 'len out of range' error instead of a
  // 'cap out of range' error when someone does make([]T, bignumber).
  // 'cap out of range' is true too, but since the cap is only being
  // supplied implicitly, saying len is clearer.
  // See golang.org/issue/4085.
  mem, overflow := math.MulUintptr(et.size, uintptr(len))
  if overflow || mem > maxAlloc || len < 0 {
   panicmakeslicelen()
  }
  panicmakeslicecap()
 }
 // 在堆上申请一片连续的内存
 return mallocgc(mem, et, true)
}
```

这个函数的主要作用就是 计算当前切片所占用的内存空间并在堆上申请一段连续的内存，所需的内存空间采用以下的方式计算：

```bash
内存空间 = 元素类型大小 * 切片容量cap
```

而元素类型的大小参照如下：

|                 类型                 |           大小            |
| :----------------------------------: | :-----------------------: |
|          bool, int8, uint8           |           1 bit           |
|            int16, uint16             |           2 bit           |
|        int32, uint32, float32        |           4 bit           |
| int, int64, uint64, float64, pointer |     8 bit (1 个字节)      |
|                string                |     16 bit (2 个字节)     |
|          长度为 n 的 array           | n \* (对应的 type 的长度) |

> TIPS：1 字节(Byte） = 8 位(bit)

`mallocgc` 是专门用于内存申请的函数，后面会详细讲解。

### 4. 切片截取

**截取** 是创建切片的一种方式，可以从数组或者切片直接截取，同时需要制定截取的起始位置。

需要关注的是下面这种截取方式： `arr1 = data[low : high : max]`。这里的三个数字都是指原数组或切片的索引值，而非数量。

这里的 **`low`是最低索引值，是闭区间**，也就是说第一个元素是位于`data`位于`low`索引处的元素；`high`是开区间，表示最后一个元素只能索引到 `high - 1`处；`max`也是开区间，表示容量为 `max - 1`。其中：`len = high - low`，`cap = max - low`，`max >= high >= low`。用下面的图来帮助说明：

![切片截取](https://pic.downk.cc/item/5f60362b160a154a67184b54.png)

基于已有的数组或者切片创建新的切片，新 slice 和老 slice 会公用底层的数组，新老 slice 对底层数组的更改都会影响彼此。需要注意的是，如果某一方执行了`append`操作引起了 **扩容** ，移动到了新位置，两者就不会影响了。**所以关键问题在于二者是否会共用底层数组**。

我们通过一个例子来说明，该例子来自于[雨痕 Go 学习笔记 P43](https://github.com/qyuhen/book/blob/master/Go%20%E5%AD%A6%E4%B9%A0%E7%AC%94%E8%AE%B0%20%E7%AC%AC%E5%9B%9B%E7%89%88.pdf)，做了一些改造：

```go
package main

import "fmt"

func main() {
    slice := []int{9, 8, 7, 6, 5, 4, 3, 2, 1, 0}
    s1 := slice[2:5]
    s2 := s1[2:6:7]

    s2 = append(s2, 55)
    s2 = append(s2, 77)

    s1[2] = 66

    fmt.Println(s1)
    fmt.Println(s2)
    fmt.Println(slice)
}

// 输出
[7 6 66]
[5 4 3 2 100 200]
[9 8 7 6 66 4 3 2 100 0]
```

让我们一步步来分析：

首先，创建 `slice`、`s1` 和 `s2`：

```go
slice := []int{9, 8, 7, 6, 5, 4, 3, 2, 1, 0}
s1 := slice[2:5]  // len为3，cap默认到底层数组的结尾
s2 := s1[2:6:7]   // len为4，cap为5

// 以上三个底层数组相同
```

![初始化slice、s1和s2](https://pic.downk.cc/item/5f604d8b160a154a671d9c16.png)

之后，向 `s2` 尾部追加一个元素：

```go
s2 = append(s2, 55)
```

`s2`的容量刚好还剩一个，直接追加，不会扩容。因为这三者此时还都共用同一个底层数组，所以这一改动，`slice`和`s1`都会受到影响：

![向s2第一次追加一个元素](https://pic.downk.cc/item/5f604f7f160a154a671e0121.png)

再次向 `s2` 追加一个元素：

```go
s2 = append(s2, 77)
```

此时，`s2` 的容量不够用，需要扩容。简单来说，扩容是新申请一块更大(具体多大，后面会说到，假设为原来的 2 倍)的内存块，将原来的数据 copy 过去，`s2` 的`array`指针指向新申请的那块内存。再次 `append` 之后：

![s2再次append后扩容](https://pic.downk.cc/item/5f6050d1160a154a671e412b.png)

最后，修改 `s1` 索引为 2 处的元素：

```go
s1[2] = 66
```

此时 `s2` 已经使用了新开辟的内存空间，不再指向`slice`和`s1`指向的那个数组，因此 `s2` 不会受影响：

![修改s1](https://pic.downk.cc/item/5f605211160a154a671e80b5.png)

后面打印 `s1` 的时候，只会打印出 `s1` 长度以内的元素。所以，只会打印出 3 个元素，虽然它的底层数组不止 3 个元素。

### 5. append 扩容规则

之前说过，扩容是新申请一块更大的内存块，将原来的数据 copy 过去，原来切片的`array`指针指向新申请的那块内存。这里我们探讨这个“更大”到底是多大：

**第一步，预估扩容后的容量 newCap：**

```go
data = []int{1,2}
data = appand(data,3,4,5)
```

扩容前的容量 `oldCap = 2`，新增 3 个元素，理论上应该扩容到 `cap=5`，之后会进行预估，求得 `newCap` 规则如下：

- 如果 $oldCap * 2 < cap$，那么 `newCap = cap`；

- 否则
  - 如果 `扩容前元素个数oldLen < 1024​` ，那么直接翻倍，即 `newCap = oldCap * 2`；
  - 否则(即 `扩容前元素个数oldLen >= 1024` )，就先扩容 四分之一，也就是 **1.25 倍**，即 `newCap = oldCap * 1.25`。

即：![预估规则](https://pic.downk.cc/item/5f605756160a154a671fb153.jpg)

这段规则的源码位于 `/usr/local/go/src/runtime/slice.go`：

```go
func growslice(et *_type, old slice, cap int) slice {
 ...
    newcap := old.cap
 doublecap := newcap + newcap
 if cap > doublecap {
  newcap = cap
 } else {
  if old.len < 1024 {
   newcap = doublecap
  } else {
   // Check 0 < newcap to detect overflow
   // and prevent an infinite loop.
   for 0 < newcap && newcap < cap {
    newcap += newcap / 4
   }
   // Set newcap to the requested cap when
   // the newcap calculation overflowed.
   if newcap <= 0 {
    newcap = cap
   }
  }
 }
    ...
}
```

上述例子中，`oldCap=2`，至少需要扩容到`cap=5`，根据预估规则，因为 `oldCap*2=4 < 5`，因此 `newCap=cap=5`，即预估结果为`newCap=5`。

**第二步，确定实际分配的内存，匹配到合适的内存规格**

**`理论上所需要内存 = 预估容量 * 元素类型大小`**，难道直接就会分配这么多的内存吗？并不是。

首先元素类型大小已在 “一.3”中说明过，此处 int 类型的大小是 8bit(1 个字节)。接着看`growslice`函数：

```go
func growslice(et *_type, old slice, cap int) slice {
    ...
    var overflow bool
 var lenmem, newlenmem, capmem uintptr
 // Specialize for common values of et.size.
 // For 1 we don't need any division/multiplication.
 // For sys.PtrSize, compiler will optimize division/multiplication into a shift by a constant.
 // For powers of 2, use a variable shift.
 switch {
 case et.size == 1:
  lenmem = uintptr(old.len)
  newlenmem = uintptr(cap)
  capmem = roundupsize(uintptr(newcap))
  overflow = uintptr(newcap) > maxAlloc
  newcap = int(capmem)
    case et.size == sys.PtrSize:
  lenmem = uintptr(old.len) * sys.PtrSize
  newlenmem = uintptr(cap) * sys.PtrSize
  capmem = roundupsize(uintptr(newcap) * sys.PtrSize)
  overflow = uintptr(newcap) > maxAlloc/sys.PtrSize
  newcap = int(capmem / sys.PtrSize)
    ....
}
```

在这里，`sys.PtrSize = 8`，`et`类型是 `int`，所以 `et.size == sys.PtrSize`为 `true`，则 `newcap * sys.PtrSize = 5 * 8 = 40`。我们看看 `roundupsize`这个函数，位于 `/usr/local/go/src/runtime/msize.go`：

```go
// Returns size of the memory block that mallocgc will allocate if you ask for the size.
func roundupsize(size uintptr) uintptr {
 if size < _MaxSmallSize {
  if size <= smallSizeMax-8 {
   return uintptr(class_to_size[size_to_class8[(size+smallSizeDiv-1)/smallSizeDiv]])
  } else {
   // ...
  }
 }
 ...
}
```

其中，`_MaxSmallSize = 32768`，`smallSizeMax = 1024`，`smallSizeDiv = 8`，而传进来的 `size = 40`。而：

```go
var class_to_size = [_NumSizeClasses]uint16{0, 8, 16, 32, 48, 64, 80, 96, 112, 128, 144, 160, 176, 192, 208, 224, 240, 256, 288, 320, 352, 384, 416, 448, 480, 512, 576, 640, 704, 768, 896, 1024, 1152, 1280, 1408, 1536, 1792, 2048, 2304, 2688, 3072, 3200, 3456, 4096, 4864, 5376, 6144, 6528, 6784, 6912, 8192, 9472, 9728, 10240, 10880, 12288, 13568, 14336, 16384, 18432, 19072, 20480, 21760, 24576, 27264, 28672, 32768}
var size_to_class8 = [smallSizeMax/smallSizeDiv + 1]uint8{0, 1, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15, 16, 16, 17, 17, 18, 18, 18, 18, 19, 19, 19, 19, 20, 20, 20, 20, 21, 21, 21, 21, 22, 22, 22, 22, 23, 23, 23, 23, 24, 24, 24, 24, 25, 25, 25, 25, 26, 26, 26, 26, 26, 26, 26, 26, 27, 27, 27, 27, 27, 27, 27, 27, 28, 28, 28, 28, 28, 28, 28, 28, 29, 29, 29, 29, 29, 29, 29, 29, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31}
```

所以上面`roundupsize`会返回：

```go
class_to_size[size_to_class8[(size+smallSizeDiv-1)/smallSizeDiv]] = 48
```

在`growslice`中，`capmem = 48`，则最后计算得到的 `newcap = int(capmem / sys.PtrSize) = int(48 / 8) = 6`，即最终扩容后的容量为 `6`。而不是之前预估的 `5`。

总结一下，首先使用预估规则预估一下需要的容量(本例中为 5)，然后用这个容量乘以 slice 元素的大小(单位是 bit，本例中 int 为 8)，之后根据在 `class_to_size` 中选择合适大小的值，比如 40，那应该选择比 40 大的更小的那个 48，这就是申请到的真正的容量内存，最后用真正的容量大小除以元素大小，即可得到真正的扩容后的 slice 的`cap`。

### 6. slice 作为函数参数

函数调用处的参数称为 **实参**，函数定义处的参数称为 **形参**。形参是实参的拷贝，会生成一个新的切片，但二者指向底层数组的指针相同。

**当函数中没有出现扩容时：**

```go
func main() {
    a := []int{1,2,3,4,5,6}
    fmt.Println(a)  // 输出 [1,2,3,4,5,6]
    t1(a)
    fmt.Println(a)  // 输出 [1,66,3,4,5,6]
}

func t1(s []int) {
    s[1] = 66
}
```

**当函数中出现扩容时：**

```go
func main() {
    a := []int{1,2,3,4,5,6}
    fmt.Println(a)  // 输出 [1,2,3,4,5,6]
    t1(a)
    fmt.Println(a)  // 输出 [1,2,3,4,5,6]
}

func t2(s []int) {
    s = append(s, 66)
}
```

扩容后，指向的底层数组不同，互不影响。

## 三、字符串(String)

字符串是 Go 语言中最常用的基础数据类型之一，虽然字符串往往被看做一个整体，但是实际上字符串是一片连续的内存空间，我们也可以将它理解成一个由字符组成的数组。

在设计上，Go 语言中的`string`是一个只读的字节数组。当然，只读只意味着字符串会分配到只读的内存空间并且这块内存不会被修改，在运行时我们其实还是可以将这段内存拷贝到堆或者栈上，将变量的类型转换成 `[]byte` 之后就可以进行，修改后通过类型转换就可以变回 `string`，Go 语言只是不支持直接修改 `string` 类型变量的内存空间。

`string`的底层结构如下：

```go
// /usr/local/go/src/runtime/string.go
type stringStruct struct {
 str unsafe.Pointer
 len int
}
```

可以看到和上面的切片结构非常相似，只是少了表示容量的`cap`。这是因为，字符串作为只读类型，我们并不会对齐进行扩容操作进而改变其自身的内存空间，**所有在字符串上执行的写入操作都是通过拷贝实现的**。

关于字符串，讨论最多的是 `string`和`[]byte`互相转换的性能问题，在底层是通过 `stringtoslicebyte` 和 `slicebytetostring`两个函数实现的，其中出现了内存分配的情况，这里不做细究。

在说`unsafe` 那篇文章里，提到了 **实现`string`和`[]byte` 的零拷贝转换**：这里再复习一下：

```go
func stringToBytes(s string)[]byte{
    return *(*[]byte)(unsafe.Pointer(&s))
}

func bytesToString(b []byte)string{
    return *(*string)(unsafe.Pointer(&b))
}
```
