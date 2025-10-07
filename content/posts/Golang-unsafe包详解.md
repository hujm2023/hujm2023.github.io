---
title: Golang-unsafe包详解
author: JemmyHu(hujm20151021@gmail.com)
toc: true
mathjax: true
summary:
categories: [技术博客, 技术细节, Golang]
tags: [Golang, unsafe包]
comment: true
date: 2020-09-17 01:53:29
cover:
  image: https://pic.downk.cc/item/5f5f5567160a154a67e8ec80.png
---

## 1. `Go`语言指针的限制

`go`语言中也有指针，但相对`C语言`的指针来说，有了很多限制，但这也算是`go`的成功之处：既可以享受指针带来的便利，又避免了指针过度使用带来的危险。主要的限制如下：

1. `go`中指针不能进行数学运算;

```go
func main() {
    num := 1
    pNum := &num

    pNum++  // invalid operation: p++ (non-numeric type *int)
}

```

2. 不同类型的指针不能相互转换

```go
func main() {
    var a int
    a = 10

    var f *float32
    f = &a  // cannot use &a (type *int) as type *float32 in assignment
}
```

3. 不同类型的指针之间不能使用`==`或`!=`进行比较，也不能相互赋值

```go
func main() {
    var a int
    var b float32

    a = 1
    b = 3.14

    pa := &a
    pb := &b

    fmt.Println(pa == nil)
    fmt.Println(pa == pb)  // invalid operation: pa == pb (mismatched types *int and *float32)
    pa = pb  // cannot use pb (type *float32) as type *int in assignment
}
```

只有在两个指针类型相同或者可以相互转换的情况下，才可以对两者进行比较。另外，指针可以通过 `==` 和 `!=` 直接和 `nil` 作比较。

## 2. `unsafe`包介绍

`unsafe` 包，“不安全”，为何不安全？是因为它可以使得用户绕过 `go` 的类型规范检查，能够对指针以及其指向的区域进行读写操作，即“允许程序无视 type 体系对任意类型内存进行读写”。因此使用时要格外小心。

`unsafe`包中只有很简单的几个函数和定义:

```go

package unsafe

// 任意go表达式的类型。只是为了文档而声明的类型，实际上它并不是unsafe包的一部分
type ArbitraryType int

// 任意类型代表的指针
type Pointer *ArbitraryType

// 返回对象x所占有的的内存大小(byte为单位)，不包含x中引用类型所占有的内存大小
func Sizeof(x ArbitraryType) uintptr

// 返回x所在结构体的起始内存地址到x所对应属性两者距离，单位为byte，参数x的格式应该是structValue.field
func Offsetof(x ArbitraryType) uintptr

// 内存对齐时使用，这里暂时不研究
func Alignof(x ArbitraryType) uintptr
```

与此同时，`unsafe`包提供了两个很重要的功能：

1. `任何类型的指针` 和 `unsafe.Pointer` 可以相互转换。
2. `uintptr` 类型和 `unsafe.Pointer` 可以相互转换。

即 `任何数据类型的指针 <----> unsafe.Pointer <----> uintptr`

上述的功能有何用途？答： **`Pointer`允许程序无视 type 体系对任意类型内存进行读写**。

如何理解这句话？因为`unsafe.Pointer`不能直接进行数学运算，但是我们可以将其转换成`uintptr`，对`uintptr`进行对应的数学运算(比如内存复制与内存偏移计算)，计算之后再转换成`unsafe.Pointer`类型。

有了这个基础，我们可以干好多“见不得光”的事，比如 底层类型相同的数组之间的转换、使用 sync/atomic 包中的一些函数、访问并修改 `Struct` 的私有字段等场景。

## 3. `unsafe`包的使用场景

### 场景一：访问并修改 `struct` 的私有属性

先从一个 demo 开始：

```go
package main
// unsafe修改struct私有属性
type user struct {
    name string
    age  int
    company string
}

func main() {
    u := new(user)  // A
    fmt.Println(*u)  // { 0}

    uName := (*string)(unsafe.Pointer(u))  // B
    *uName = "Jemmy"
    fmt.Println(*u)  // {Jemmy 0}

    uAge := (*int)(unsafe.Pointer(uintptr(unsafe.Pointer(u)) + unsafe.Offsetof(u.age)))  // C
    *uAge = 23
    fmt.Println(*u)  // {Jemmy 23}

    uCompany := (*string)(unsafe.Pointer(uintptr(unsafe.Pointer(u)) + unsafe.Offsetof(u.company)))  // D
    *uCompany = "吹牛逼技术有限公司"
    fmt.Println(*u)  // {Jemmy 23 吹牛逼技术有限公司}
}
```

在 A 处，我们新建一个`user`对象，使用`new`直接返回此类对象的指针。在这里要注意，在`go`中，对一个`struct`进行内存分配，实际上是分配的一块连续的空间，而`new`返回的指针，其实是`struct`中第一个元素的地址。

通过上面的介绍我们知道，`unsafe.Offsetof(x ArbitraryType)` **返回 x 所在结构体的起始内存地址到 x 所对应属性两者距离，单位为 `byte`，参数 x 的格式应该是 `structValue.field`**，那么`unsafe.Offsetof(u.name)`指的就是 `u`的起始地址，到属性`name`之间有多少个`byte`。

在 C 处，因为`unsafe.Pointer`不能直接参与数学运算，所以我们先转换成`uintptr`类型，然后与`unsafe.Offsetof(u.age)`相加，就是`u`的属性`age`的地址，为`uintptr`类型，之后再转换为`unsafe.Pointer`，即可通过强制类型转换，直接去修改该属性的值。

再来看 B 处，因为`u`的地址就是其第一个属性`name`的地址，可以直接获取到。其实我们可以改成和 C 处相似的结构：`uName := (*string)(unsafe.Pointer(uintptr(unsafe.Pointer(u)) + unsafe.Offsetof(u.name)))`，效果一样。

**注意!!!**上面 C 处的语句的加号两边的对象不能直接拆开去写，也就是说，不能写成:

```go
tmp := uintptr(unsafe.Pointer(u))
uAge := (*int)(unsafe.Pointer(tmp + unsafe.Offsetof(u.age)))
```

原因是，`uintptr`这个临时变量，本身就是一个很大的整数，而程序经过一些很大的计算之后，涉及到栈的扩容，扩容之后，原来的对象的内存位置发生了偏移，而 `uintptr` 所指的整数对应的地址也就发生了变化。这个时候再去使用，由于这个整数指的地址已经不是原来的地址了，会出现意想不到的 bug。

### 场景二： 利用`unsafe`获取 slice 的长度

通过查看对应的源代码，我们知道`slice header`的结构体定义为：

```go
type slice struct {
    array unsafe.Pointer    // 元素指针 1字节
    len int                 // 长度 1字节
    cap int                 // 指针 1字节
}
```

当我们调用`make`函数创建一个新的`slice`后，底层调用的是`makeslice`，返回的是`slice`结构体:

```go
func makeslice(et *_type, len, cap int) slice
```

因此，我们可以通过`unsafe.Pointer`和`uintptr`进行转换，得到 slice 的字段值：

```go
func main() {
    s := make([]int, 10, 20)

    // slice结构体中，array类型为pointer，占1个字节8位，uintptr(unsafe.Pointer(&s))表示s的地址也是第一个属性array的地址，那么加上属性array的长度，就是下一个属性len的长度
    var sLen = (*int)(unsafe.Pointer(uintptr(unsafe.Pointer(&s)) + uintptr(8)))
    fmt.Println(*sLen, len(s)) // 10 10

    // 16的原因同上
    var sCap = (*int)(unsafe.Pointer(uintptr(unsafe.Pointer(&s)) + uintptr(16)))
    fmt.Println(*sCap, cap(s)) // 20 20
}
```

### 场景三：实现`string`和`[]byte` 的零拷贝转换

一般的做法，都需要遍历字符串或 bytes 切片，再挨个赋值。

在反射包`src/reflect/value.go`中，有下面的结构体定义：

```go
type StringHeader struct {
    Data uintptr
    Len  int
}

type SliceHeader struct {
    Data uintptr
    Len  int
    Cap  int
}
```

因此，只需共享底层的`Data`和`Len`即可：

```go
func stringToBytes(s string)[]byte{
    return *(*[]byte)(unsafe.Pointer(&s))
}

func bytesToString(b []byte)string{
    return *(*string)(unsafe.Pointer(&b))
}
```

## 4. `unsafe.Sizeof(struct) 的本质`

先看源码注释：

```go
// Sizeof takes an expression x of any type and returns the size in bytes
// of a hypothetical variable v as if v was declared via var v = x.
// The size does not include any memory possibly referenced by x.
// For instance, if x is a slice, Sizeof returns the size of the slice
// descriptor, not the size of the memory referenced by the slice.
// The return value of Sizeof is a Go constant.
// 返回对象x所占有的的内存大小(byte为单位)，不包含x中引用类型所占有的内存大小
func Sizeof(x ArbitraryType) uintptr
```

这其中比较有意思的是 **`unsafe.Sizeof(a struct)`的结果**问题，即一个`struct`的 size 值为多少的问题。

我们来观察一个有趣的事实：**一个`struct`的 size 依赖于它内部的属性的排列顺序**，即两个属性相同但排列顺序不同的`struct`的 size 值可能不同。

比如，下面这个结构体 A 的 size 是 32：

```go
type struct A{
    a bool
    b string
    c bool
}
```

而另一个和它有相同属性的结构体 B 的 size 是 24:

```go
type struct B{
    a bool
    c bool
    b string
}
```

这都是 **内存对齐**在捣鬼。我们看一下 A 和 B 的内存位置：
![struct内存位置](https://pic.downk.cc/item/5f5f5567160a154a67e8ec80.png)

如上图所示，左边为`struct A`，右边为`struct B`。而`Aligment`可以使 1,2,4 或者 8。对 A 来说，`a bool`占一个 byte，而下一个属性是`b string`，占 16 个 byte(后面会说明为什么占 2 个字节)，因此无法进行内存对齐；而对 B 来说，`a bool`和`c bool`可以放在同一个 byte 中。

在`Golang`中，各类型所占的 byte 如下

- bool,int8,uint8 --> 1 byte
- int16,uint16 --> 2 byte
- int32,uint32,float32 --> 4 byte
- int,int64,uint64,float64,pointer --> 8 byte
- string --> 16 byte (两个字节)
- 任何 slice --> 24 byte(3 个字节)
- 长度为 n 的 array --> n\*对应的 type 的长度

> 为什么`string`占到 2 个字节？因为 `string` 底层也是一个结构体，该结构体有两个域，第一个域是指向该字符串的指针，第二个域是字符串的长度，每个域占 8 个字节；
>
> 为什么任意类型的`slice`占到 3 个字节？同理，`slice`底层也是一个结构体，有三个域：
>
> ```go
> // runtime/slice.go
> type slice struct {
>    array unsafe.Pointer // 元素指针 1个字节
>    len   int // 长度 8个byte 1个字节
>    cap   int // 容量 8个byte 1个字节
> }
> ```

说到这里，你也应该明白了，`unsafe.Sizeof`总是在编译期就进行求值，而不是在运行时，而且是根据类型来求值，而和具体的值无关。(这意味着，`unsafe.Sizeof`的返回值可以赋值给`const`即常量)

可以通过下面的 demo 输出，判断你的掌握程度：

```go

package main

type user struct {
    name    string // 2字节
    age     int    // 1字节
    company string // 2字节
}

func main(){
    fmt.Println(unsafe.Sizeof(user{}))              // 输出40，5个字节，看 struct user 注释
    fmt.Println(unsafe.Sizeof(10))                  // 输出8，因为int占1字节
    fmt.Println(unsafe.Sizeof([]bool{true, false})) // 输出24，任何slice都输出24
    fmt.Println(unsafe.Sizeof([][]string{}))        // 输出24，任何slice都输出24，即使是多维数组
}
```

## 5. 参考文献

- [码农桃花源—标准库--unsafe](https://qcrao91.gitbook.io/go/biao-zhun-ku/unsafe/go-zhi-zhen-he-unsafe.pointer-you-shi-mo-qu-bie)
- [sizeof-struct-in-go](https://stackoverflow.com/questions/2113751/sizeof-struct-in-go)
