---
title: Golang-map详解
author: JemmyHu(hujm20151021@gmail.com)
toc: true
mathjax: true
summary:
categories: [技术博客, 技术细节, Golang]
tags: [Golang, map, 哈希表]
comment: true
date: 2020-09-18 23:41:39
cover:
  image: https://pic.downk.cc/item/5f61dc63160a154a6777224d.png
---

## 一、设计原理

哈希表(也就是我们说的`map`)是计算机应用领域非常重要的数据结构之一，读写的时间复杂度均是`O(1)`，是典型的 **以空间换时间** 设计。它的优点除了读写性能优异，还在于它提供了键值之间的映射，为程序设计提供了极大的方便。要想实现一个性能优异的哈希表，需要关注两个关键点：**哈希函数** 和 **冲突解决方法**。

### 1. 哈希函数

**可以将任意长度的数据 映射 到有限长度的域上**。通俗解释：你可以把它抽象成一个黑盒(一个函数 f)，它的输入是任意数据 m，输出是另一段固定范围的数据 n，即`f(m) = n`，n 可以作为 m 的特征(指纹)。

对任意两个输入`m1`和`m2`，如果他们的输出均不同，则称这个函数为 **完美哈希函数**。如果存在`m1`和`m2`，有 `f(m1) = f(m2)`，则称这个函数为 **不均匀哈希函数**，这个现象称为 **哈希碰撞**。

完美哈希函数很难找到，比较实际的做法是 **让哈希函数的结果尽可能地分布均匀，然后通过工程上的手段解决哈希碰撞的问题**。但是哈希的结果一定要尽可能均匀，结果不均匀的哈希函数会造成更多的冲突并导致更差的读写性能。

### 2. 解决哈希冲突的方法

在通常情况下，哈希函数输入的范围一定会远远大于输出的范围，所以在使用哈希表时一定会遇到冲突，哪怕我们使用了完美的哈希函数，当输入的键足够多最终也会造成冲突。

然而我们的哈希函数往往都是不完美的，输出的范围是有限的，所以一定会发生哈希碰撞，这时就需要一些方法来解决哈希碰撞的问题，常见方法的就是**开放寻址法**和**拉链法**。

#### 2.1 开放寻址法

这种方法的核心思想在于 **线性探测**，通常情况下，这种哈希表的底层数据结构就是数组。先计算`index`，判断数组的这个`index`处是否有值，如果没有，直接存入；否则从这个`index`向后遍历，直到找到一个为空的`index`。可以大致用下面的代码表示：

```go
func hash1(source string) int {
    arr := make([]string,10,10)
    index := hash(source) % len(arr)
    tmp := index
    for {
        if arr[index%len(arr)] == "" {
            return index
        }else {
            index++
        }
        if index == tmp {
            return -1  // 没找到
        }
    }
}
```

查找的时候，还是先计算 `index` ，如果数组在该位置的数刚好是要找的，直接返回，否则需要向后逐步遍历比较。在某些情况下，当装载的元素太多时，哈希表的性能会急剧下降，最差的结果就是每次增加和查找，都需要遍历整个数组，此时整个哈希表完全失效。

#### 2.2 拉链法

与开放地址法相比，拉链法是哈希表中最常见的实现方法，大多数的编程语言都用拉链法实现哈希表，它的实现比较开放地址法稍微复杂一些，但是平均查找的长度也比较短，各个用于存储节点的内存都是动态申请的，可以节省比较多的存储空间。

拉链法使用链表作为底层数据结构，我们把这个链表称为桶。这种方法对哈希冲突的解决方法是：直接在相同哈希值的结点后面增加一个链表结点。查询的时候，先找到对应链表第一个结点，之后遍历链表寻找符合要求的那个。

在一个性能比较好的哈希表中，每一个桶中都应该有 0~1 个元素，有时会有 2~3 个，很少会超过这个数量，**计算哈希**、**定位桶**和**遍历链表**三个过程是哈希表读写操作的主要开销，使用拉链法实现的哈希也有装载因子这一概念：

```bash
装载因子 := 元素数量/桶数量
```

与开放地址法一样，拉链法的装载因子越大，哈希的读写性能就越差，在一般情况下使用拉链法的哈希表装载因子都不会超过 1，当哈希表的装载因子较大时就会触发哈希的扩容，创建更多的桶来存储哈希中的元素，保证性能不会出现严重的下降。如果有 1000 个桶的哈希表存储了 10000 个键值对，它的性能是保存 1000 个键值对的 1/10，但是仍然比在链表中直接读写好 1000 倍。

## 二、用到的数据结构

我的 Go 版本：

```bash
go version go1.14.6 darwin/amd64
```

Go 语言中对哈希表的实现方案是：使用拉链法解决哈希冲突。同时使用了多个数据结构组合来标识哈希表。

在源码中，表示`map` 的结构体是 `hmap`：

```go /usr/local/go/src/runtime/map.go
// A header for a Go map.
type hmap struct {
    count     int               // 当前哈希表中元素个数，调用len(m)时直接返回此值
    flags     uint8             //
    B         uint8             // 当前哈希表持有的 buckets 数量的对数，即 buckets数量 = 2^B
    noverflow uint16            // overflow 的 buckets 的近似数(buckets<16时是准确的)
    hash0     uint32            // 哈希种子，在创建哈希表时确定的随机数，并在调用哈希函数的时候作为参数传入

    buckets    unsafe.Pointer   // 指向 buckets 数组，大小为 2^B，如果元素个数为0则为nil
    oldbuckets unsafe.Pointer   // 渐进式扩容时用于保存之前的 buckets，扩容的时候，buckets 长度会是 oldbuckets 的两倍
    nevacuate  uintptr          // 指示扩容进度，表示即将迁移的旧桶编号

    extra *mapextra // optional fields
}

// mapextra holds fields that are not present on all maps. 溢出桶相关信息
type mapextra struct {
    overflow    *[]*bmap  // 目前已经使用的溢出桶的地址
    oldoverflow *[]*bmap  // 在扩容阶段存储旧桶用到的溢出桶的地址

    nextOverflow *bmap    // 指向下一个空闲溢出桶
}
```

`buckets` 是一个指针，最终指向的是一个结构体：

```go /usr/local/go/src/runtime/map.go
// A bucket for a Go map.
type bmap struct {
    tophash [bucketCnt]uint8
}
```

`bmap` 结构体其实不止包含 `tophash` 字段，由于哈希表中可能存储不同类型的键值对并且 Go 语言也不支持泛型，所以键值对占据的内存空间大小只能在编译时进行推导，这些字段在运行时也都是通过计算内存地址的方式直接访问的，所以它的定义中就没有包含这些字段，实际上的 `bmap` 是这样的：

```go
type bmap struct {
    topbits  [8]uint8       // tophash数组
    keys     [8]keytype     // key数组
    values   [8]valuetype   // value数组
    pad      uintptr
    overflow uintptr    // 当当前桶存满时，发现还有可用的溢出桶，就会用此指针链接一个溢出桶，溢出桶也是 bmap 结构
}
```

![map数据结构](https://pic.downk.cc/item/5f6182f1160a154a67617498.png)

如上图所示，`hmap`的桶就是 `bmap`，每一个 `bmap` 最多能存储 8 个键值对，这些键值对之所以会落在同一个桶，是因为他们经过哈希计算之后，得到的哈希结果是 “一类的”。当单个桶中存储的数据过多而无法装满时，就会使用 `extra.overflow` 中的桶存储溢出的数据。上面两种桶在内存中是连续的，我们暂且称之为 **常规桶** 和 **溢出桶**。

我们来看看 `bmap` 的内部组成：

![bmap内部组成](https://pic.downk.cc/item/5f61dc63160a154a6777224d.png)

最开始是 8 个 `tophash`，每个 `tophash` 都是对应哈希值的高 8 位。需要注意的是，key 和 value 是各自放在一起的，这样的好处是为了**padding** 时节省空间。每一个桶被设计成最多只能存放 8 个键值对，如果有第 9 个键值对落入当前的桶，那就需要再构建一个桶(溢出桶)，然后用 `overflow` 指针连接起来。

## 三、使用

### 1. 初始化

无论是通过字面量还是运行时，最终底层都会调用 `makemap` 方法：

```go
func makemap(t *maptype, hint int, h *hmap) *hmap {
    // 计算哈希占用的内存是否溢出或者产出能分配的最大值
    mem, overflow := math.MulUintptr(uintptr(hint), t.bucket.size)
    if overflow || mem > maxAlloc {
        hint = 0
    }


    if h == nil {
        h = new(hmap)
    }

        // 获取随机的哈希种子
    h.hash0 = fastrand()

    // 根据传入的hint计算需要的最少的桶的数量
    B := uint8(0)
    for overLoadFactor(hint, B) {
        B++
    }
    h.B = B

    // 创建用于保存桶的数组
    if h.B != 0 {
        var nextOverflow *bmap
        h.buckets, nextOverflow = makeBucketArray(t, h.B, nil)
        if nextOverflow != nil {
            h.extra = new(mapextra)
            h.extra.nextOverflow = nextOverflow
        }
    }

    return h
}
```

需要注意的是 `makeBucketArray` 函数，这个函数会根据传入的 `B` 计算出的需要创建的桶的数量 在内存中分配一片连续的空间用于存储数据。当桶的数量小于 $2^4$ 时，由于数据较少，使用溢出桶的可能性比较低，这时会省略创建的过程以减少额外开销；当桶的数量多于 $2^4$ 时，就会额外创建 $2^{B-4}$ 个溢出桶。正常情况下，溢出桶和常规桶在内存中的存储空间是连续的，只不过被 `hmap` 的不同字段引用。

> 另外注意`makemap` 的返回，是一个 `*hmap` ，指针类型，这个时候传给函数在函数中改变的就是原来的 `map` ，即 改变`map`类型的形参，是可以影响实参的。这一点和之前的 `slice` 不同，`slice` 返回的是一个 `slice` 结构体，虽底层共用数组，但是扩容后就与原来的数据脱钩了。

举个例子，下面的代码：

```go
map := make(map[string]string, 10)
```

Go 源码中的负载因子是 `6.5` ，在源码 `/usr/local/go/src/runtime/map.go:70` 可以找到：

```go
// Maximum average load of a bucket that triggers growth is 6.5.
// Represent as loadFactorNum/loadFactDen, to allow integer math.
loadFactorNum = 13
loadFactorDen = 2
```

这里的`map` 的键值对个数是 10，根据 `负载因子 = 键值对个数/桶个数`，得到 需要的桶的个数为 2。此时不会创建更多的溢出桶。

### 2. 写

源码中执行 **写入** 操作的是 `mapassign` 函数，该函数较长，我们分步来看(每一步我会在关键位置写上注释，也更容易理解过程)。

1. **首先，函数会根据传入的键计算哈希，确定所在的桶：**

```go
func mapassign(t *maptype, h *hmap, key unsafe.Pointer) unsafe.Pointer {
    // a.调用key类型对应的哈希算法得到哈希
    hash := t.hasher(key, uintptr(h.hash0))

    // b.设置 写 标志位
    h.flags ^= hashWriting

    if h.buckets == nil {
        h.buckets = newobject(t.bucket) // newarray(t.bucket, 1)
    }

again:
    // c.根据 hash 计算位于哪个 bucket
    bucket := hash & bucketMask(h.B)
    if h.growing() {
        // d.如果 map 正在扩容，此操作确保此 bucket 已经从 hmap.oldbuckets 被搬运到 hmap.buckets
        growWork(t, h, bucket)
    }
    // e.取得 bucket 所在的内存地址
    b := (*bmap)(unsafe.Pointer(uintptr(h.buckets) + bucket*uintptr(t.bucketsize)))
    // f.计算此bucket中的tophash，方法是：取高8位
    top := tophash(hash)
    // ...
}
```

在 64 位机器上，步骤 a 计算得到的 hash 值共有 64 个 bit 位。之前提到过，`hmap.B` 表示桶的数量为 $2^{h.B}$。这里用得到的哈希值的**最后 `B` 个 bit 位表示落在了哪个桶中**，用哈希值的 **高 8 位表示此 key 在 bucket 中的位置**。

> 还是以上面的`map = make(map[string]int, 10)`为例，计算可知 `B=2`，则应该用后 2 位用来选择桶，高 8 位用来表示 tophash。 某个 key 经过哈希之后得到的 `hash=01100100 001011100001101110110010011011001000101111000111110010 01`，后两位 `01` 代表 1 号桶。

2. **然后，会有两层循环，最外层循环 `bucket` 以及其链接的溢出桶(如果有的话)，内存逐个遍历所有的`tophash`：**

```go
    var inserti *uint8  // 目标元素在桶中的索引
    var insertk unsafe.Pointer // 桶中键的相对地址
    var elem unsafe.Pointer  // 桶中值的相对地址
bucketloop:
 // 最外层是一个死循环，其实是当前 bucket 后面链接的溢出桶(overflow)
    for {
        // bucketCnt=8，因为一个bucket最多只能存储8个键值对
        for i := uintptr(0); i < bucketCnt; i++ {
        // 找到一个tophash不同的
        if b.tophash[i] != top {
            // isEmpty判断当前tophash是否为正常tophash值而不是系统迁移标志
            if isEmpty(b.tophash[i]) && inserti == nil {
                inserti = &b.tophash[i]
                insertk = add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize))
                elem = add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
                // 已经找到一个可以放置的位置了，为什么不直接break掉？是因为有可能K已经存在，需要找到对应位置然后更新掉
            }
            // 如果余下位置都是空的，则不再需要往下找了
            if b.tophash[i] == emptyRest {
                break bucketloop
            }
        continue
        }
        // tophash 相同后，还需要再比较实际的key是否相同
        k := add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize))
        if t.indirectkey() {
            k = *((*unsafe.Pointer)(k))
        }
        if !t.key.equal(key, k) {
            continue
        }
        // key已经在map中了，更新之
        if t.needkeyupdate() {
            typedmemmove(t.key, k, key)
        }
        elem = add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
        goto done
    }
    // 外层循环接着遍历这个bucket后面链接的overflow
    ovf := b.overflow(t)
    if ovf == nil {
        break
    }
    b = ovf
 }
```

在上述代码中有出现`isEmpty` 以及 `emptyRest` 等标志位，这其实是 `tophash` 的状态值，在源码 `/usr/local/go/src/runtime/map.go:92` 中可以找到：

```go
 // // Possible tophash values. We reserve a few possibilities for special marks.
 emptyRest      = 0 // 这个 cell 是空的, 并且在当前bucket的更高的index 或者 overflow中，其他的都是空的
 emptyOne       = 1 // 这个 cell 是空的
 evacuatedX     = 2 // K-V 已经搬迁完毕，但是 key 在新的 bucket 的前半部分(扩容时会提到)
 evacuatedY     = 3 // 同上，key 在新的 bucket 的后半部分
 evacuatedEmpty = 4 // cell 是空的，并且已经被迁移到新的 bucket 上
 minTopHash     = 5 // 正常的 tophash 的最小值
```

由此也可知，**正常的 `tophash` 是 大于 `minTopHash` 的**。

3. **如果此时 (键值对数已经超过负载因子 或者 已经有太多的溢出桶) && 当前没有处在扩容阶段，那么 开始扩容：**

```go
 // If we hit the max load factor or we have too many overflow buckets,
 // and we're not already in the middle of growing, start growing.
 if !h.growing() && (overLoadFactor(h.count+1, h.B) || tooManyOverflowBuckets(h.noverflow, h.B)) {
    hashGrow(t, h)
    goto again // Growing the table invalidates everything, so try again
 }
```

具体的扩容过程后面再细说，这里暂不讨论。

4. **如果没有找到合适的 cell 来存放这个键值对(桶满了)，则 使用预先申请的保存在 `hmap.extra.nextoverflow` 指向的溢出桶 或者 创建新桶 来保存数据，之后将键值对插入到相应的位置：**

```go
    if inserti == nil {
        // all current buckets are full, allocate a new one.
        newb := h.newoverflow(t, b)
        inserti = &newb.tophash[0]
        insertk = add(unsafe.Pointer(newb), dataOffset)
        elem = add(insertk, bucketCnt*uintptr(t.keysize))
    }

    // store new key/elem at insert position
    if t.indirectkey() {
        kmem := newobject(t.key)
        *(*unsafe.Pointer)(insertk) = kmem
        insertk = kmem
    }
    if t.indirectelem() {
        vmem := newobject(t.elem)
        *(*unsafe.Pointer)(elem) = vmem
    }
    // 将键值对移动到对应的空间
    typedmemmove(t.key, insertk, key)
    *inserti = top
    h.count++
```

而使用预分配的溢出桶还是申请新的桶，在 `newoverflow` 函数中：

```go
func (h *hmap) newoverflow(t *maptype, b *bmap) *bmap {
    var ovf *bmap
    if h.extra != nil && h.extra.nextOverflow != nil {
        // 如果有预分配的 bucket
        ovf = h.extra.nextOverflow
        if ovf.overflow(t) == nil {
            // 并且预分配的溢出桶还没有使用完，则使用这个溢出桶，并更新 h.extra.nextOverflow 指针
            h.extra.nextOverflow = (*bmap)(add(unsafe.Pointer(ovf), uintptr(t.bucketsize)))
        } else {
            // 预分配的溢出桶已经用完了，则置空 h.extra.nextOverflow指针
            ovf.setoverflow(t, nil)
            h.extra.nextOverflow = nil
        }
    } else {
        // 没有可用的溢出桶，则申请一个新桶
        ovf = (*bmap)(newobject(t.bucket))
    }
    // 更新h.noverflow(overflow的树木)，如果h.B < 16，则自增1，否则“看可能性”自增(没啥用，感兴趣可以自己研究一下)
    h.incrnoverflow()
    if t.bucket.ptrdata == 0 {
        h.createOverflow()
        *h.extra.overflow = append(*h.extra.overflow, ovf)
    }
    b.setoverflow(t, ovf)
    return ovf
}
```

### 3. 读

我们再来说说 **读** 的过程。`map` 的读取有两种方式：带 `comma` 和 不带 `comma` 的。这两种方式，其实底层调用的分别是：

```go
func mapaccess1(t *maptype, h *hmap, key unsafe.Pointer) unsafe.Pointer       // v1 := m[key]
func mapaccess2(t *maptype, h *hmap, key unsafe.Pointer) (unsafe.Pointer, bool)  // v2, isExist := m[key]
```

这两个函数大同小异，我们只看 `mapaccess1`。我们还是采用分步的方式来从源码中探究细节：

1. **根据 `key` 计算得到 `hash` 值，同时确定在哪个 `bucket` 中寻找：**

```go
// 这个函数永远不会返回 nil ，如果map是空的，则返回对应类型的 零值
if h == nil || h.count == 0 {
    if t.hashMightPanic() {
        t.hasher(key, 0) // see issue 23734
    }
    return unsafe.Pointer(&zeroVal[0])
}
if h.flags&hashWriting != 0 {
    throw("concurrent map read and map write")
}
// 得到 hash 值
hash := t.hasher(key, uintptr(h.hash0))
m := bucketMask(h.B)  // 本例中m=31
// 得到 bucket
b := (*bmap)(add(h.buckets, (hash&m)*uintptr(t.bucketsize)))
if c := h.oldbuckets; c != nil {
    // 正处在扩容阶段
    // 如果不是等量扩容(后面会讲到)
    if !h.sameSizeGrow() {
        // There used to be half as many buckets; mask down one more power of two.
        // 非等量扩容，那就是渐进式扩容，在原来基础上增加了2倍，为了得到原来的，这里除以2
        m >>= 1  // m=15
    }
    oldb := (*bmap)(add(c, (hash&m)*uintptr(t.bucketsize)))
    // 是否处于扩容阶段
    if !evacuated(oldb) {
        b = oldb
    }
}
top := tophash(hash)
```

2. **和前面 写 的过程类似，也是两个大循环，外层遍历 `bucket` 以及链接在后面的 溢出桶，内层遍历每个 `bucket` 中的 `tophash`，直至找到需要的 键值对：**

```go
bucketloop:
    // 外层循环溢出桶
    for ; b != nil; b = b.overflow(t) {
        // bucketCnt=8
        for i := uintptr(0); i < bucketCnt; i++ {
            if b.tophash[i] != top {
                // 和当前index的tophash不相等，并且后面的cell都是空的，说明后面就没不要再去遍历了，直接退出循环，返回对应元素的零值
                if b.tophash[i] == emptyRest {
                    break bucketloop
                }
                continue
            }
            // 找到对应的 key
            k := add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize))
            if t.indirectkey() {
                k = *((*unsafe.Pointer)(k))
            }
            // tophash相同，还要判断完整的key是否相同
            if t.key.equal(key, k) {
                e := add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
                if t.indirectelem() {
                    e = *((*unsafe.Pointer)(e))
                }
                // 根据偏移找到对应的value，直接返回
                return e
            }
        }
    }
 // 没找到，返回对应类型的零值
 return unsafe.Pointer(&zeroVal[0])
```

另外，编译器还会根据 `key` 的类型，将具体的操作用更具体的函数替换，比如 `string` 对应的是 `mapaccess1_faststr(t *maptype, h *hmap, ky string) unsafe.Pointer`，函数的参数直接就是具体的类型，这么做是因为提前知道了元素类型，而且由于 `bmap` 中 `key` 和 `value` 各自放在一起，内存布局非常清晰，这也是前面说的 “减少 padding 带来的浪费”的原因。

### 4. 扩容

在前面介绍 **写** 过程时，我们跳过了有关扩容的内容，现在回过头来看一下：

```go
func mapassign(t *maptype, h *hmap, key unsafe.Pointer) unsafe.Pointer {
    // ...
    if !h.growing() && (overLoadFactor(h.count+1, h.B) || tooManyOverflowBuckets(h.noverflow, h.B)) {
        hashGrow(t, h)
        goto again
    }
    // ...
}

// 判断h是否正在扩容。 扩容结束之后，h.oldbuckets 会被置空
func (h *hmap) growing() bool {
    return h.oldbuckets != nil
}

// 判断map中的键值对数目与已有的buckets 是否超过负载因子 即 count/2^B 与 6.5的大小关系
func overLoadFactor(count int, B uint8) bool {
    return count > bucketCnt && uintptr(count) > loadFactorNum*(bucketShift(B)/loadFactorDen)
}

// 是否有太多的bucket
func tooManyOverflowBuckets(noverflow uint16, B uint8) bool {
    // If the threshold is too low, we do extraneous work.
    // If the threshold is too high, maps that grow and shrink can hold on to lots of unused memory.
    // "too many" means (approximately) as many overflow buckets as regular buckets.
    if B > 15 {
        B = 15
    }
    // 翻译一下这条语句：
    //   如果 B < 15， 即 bucket总数 < 2^15 时，overflow的bucket数目不超过 2^B
    //      如果 B >= 15，即 bucket总数 > 2^15 时，overflow的bucket数目不超过 2^15
    // 即 noverflow >= 2^(min(B,15))
    return noverflow >= uint16(1)<<(B&15)
}
```

从现实角度出发，会有以下两种情形：

1. 在没有溢出、且所有的桶都装满了的情况下，装载因子是 8，超过了 6.5，表明很多的 `bucket` 中都快装满了，读写效率都会降低，此时进行扩容是必要的；
2. 当装载因子很小、但是 `bucket` 很多的时候，`map` 的读写效率也会很低。什么时候会出现 “键值对总数很小、但 bucket 很多”的情况呢？不停地插入、删除元素。当插入很多元素时，导致创建了更多的 `bucket` ，之后再删除，导致某个 `bucket` 中的键值对数量非常少。“这就像是一座空城，房子很多，但是住户很少，都分散了，找起人来很困难。”

对于上述两种情况，Go 有着不同的策略：

1. 对于第一种情况，城中人多房少，直接将 `B` 加一，建更多的房子即可；
2. 对第二种情况，新开辟一块同样大小的空间，然后将旧空间中的键值对全部搬运过去，然后重新组织。

**扩容** 最基础的一个操作是 将原有的键值对搬到新开辟的空间，如果键值对数量太多，将严重影响性能。因此对于情况一，Go 采取 **渐进式扩容**，并不会一次全部搬完，每次最多只搬迁 2 个 bucket；第二种情况，称之为 **等量扩容** ，可以理解成“内存整理”。接下来我们通过源码来分析实际的过程：

执行扩容的函数是 `hashGrow` ， `hashGrow()` 函数实际上并没有真正地“搬迁”，它只是分配好了新的 buckets，并将老的 `buckets` 挂到了 `oldbuckets` 字段上。真正搬迁 `buckets` 的动作在 `growWork()` 函数和 `evacuate()` 函数中，而调用 `growWork()` 函数的动作是在 `mapassign` 和 `mapdelete` 函数中。也就是插入或修改、删除 `key` 的时候，都会尝试进行搬迁 `buckets` 的工作。先检查 `oldbuckets` 是否搬迁完毕，具体来说就是检查 `oldbuckets` 是否为 `nil`。

我们来看看 `hashGrow` 函数：

```go
func hashGrow(t *maptype, h *hmap) {
    // If we've hit the load factor, get bigger.
    // Otherwise, there are too many overflow buckets,
    // so keep the same number of buckets and "grow" laterally.
    // 首先通过 是否超过负载因子 判断进行渐进式扩容还是等量扩容
    bigger := uint8(1)  // 默认等量扩容
    if !overLoadFactor(h.count+1, h.B) {
        // 如果没有超过负载因子，则进行等量扩容
        bigger = 0
        h.flags |= sameSizeGrow
    }
    // 申请新的 bucket 空间，并将原来的 h.buckets 字段 转移到 h.oldbuckets
    oldbuckets := h.buckets
    newbuckets, nextOverflow := makeBucketArray(t, h.B+bigger, nil)

    // 将以前原有的buckets的标志位也转移到新申请的buckets去
    flags := h.flags &^ (iterator | oldIterator)
    if h.flags&iterator != 0 {
        flags |= oldIterator
    }
    // 执行grow操作 (atomic wrt gc)
    h.B += bigger
    h.flags = flags
    h.oldbuckets = oldbuckets
    h.buckets = newbuckets
    h.nevacuate = 0  // h.nevacuate指示扩容进度，表示当前正在搬迁旧的第几个bucket
    h.noverflow = 0  // 将溢出桶个数置为零

    // 将extra中的overflow扔到oldoverflow中去
    if h.extra != nil && h.extra.overflow != nil {
        // Promote current overflow buckets to the old generation.
        if h.extra.oldoverflow != nil {
            throw("oldoverflow is not nil")
        }
        h.extra.oldoverflow = h.extra.overflow
        h.extra.overflow = nil
    }
    if nextOverflow != nil {
        if h.extra == nil {
            h.extra = new(mapextra)
        }
        h.extra.nextOverflow = nextOverflow
    }

    // the actual copying of the hash table data is done incrementally
    // by growWork() and evacuate().
}
```

第 17 行涉及到的 `flag` 如下：

```go
// flags
iterator     = 1 // 可能有迭代器使用 buckets
oldIterator  = 2 // 可能有迭代器使用 oldbuckets
hashWriting  = 4 // 有协程正在向 map 中写入 key
sameSizeGrow = 8 // 等量扩容（对应第二种情况）
```

我们再来看看实际执行扩容的 `growWork` 和 `evacuate`：

```go
func growWork(t *maptype, h *hmap, bucket uintptr) {
    // 确认搬迁老的 bucket 对应正在使用的 bucket
    evacuate(t, h, bucket&h.oldbucketmask())

    // 还没搬迁完成的话，再搬迁一个 bucket，以加快搬迁进程
    if h.growing() {
        evacuate(t, h, h.nevacuate)
    }
}
```

`evacuate` 函数非常长，我们还是逐步去深入：

```go
func evacuate(t *maptype, h *hmap, oldbucket uintptr) {
    // 定位到老的bucket
    b := (*bmap)(add(h.oldbuckets, oldbucket*uintptr(t.bucketsize)))
    newbit := h.noldbuckets() // 存放增长之前的bucket数，结果为 2^B
    if !evacuated(b) {
    // TODO: reuse overflow buckets instead of using new ones, if there
    // is no iterator using the old buckets.  (If !oldIterator.)

    // xy contains the x and y (low and high) evacuation destinations.
            /*
            // evacDst表示搬迁的目的区域.
            type evacDst struct {
                    b *bmap          // 搬去的bucket
                i int            // bucket中键值对的index
                k unsafe.Pointer // pointer to current key storage
                e unsafe.Pointer // pointer to current elem storage
            }
            */
            // 这里设置两个目标桶，如果是等量扩容，则只会初始化其中一个；
            // xy 指向新空间的高低区间的起点
        var xy [2]evacDst
        x := &xy[0]
        x.b = (*bmap)(add(h.buckets, oldbucket*uintptr(t.bucketsize)))
        x.k = add(unsafe.Pointer(x.b), dataOffset)
        x.e = add(x.k, bucketCnt*uintptr(t.keysize))

        // 如果是翻倍扩容，则同时初始化，之后会将旧桶中的键值对“分流”到两个新的目标桶中
        if !h.sameSizeGrow() {
            // Only calculate y pointers if we're growing bigger.
            // Otherwise GC can see bad pointers.
            y := &xy[1]
            y.b = (*bmap)(add(h.buckets, (oldbucket+newbit)*uintptr(t.bucketsize)))
            y.k = add(unsafe.Pointer(y.b), dataOffset)
            y.e = add(y.k, bucketCnt*uintptr(t.keysize))
        }

        // 遍历所有的 bucket，包括 overflow buckets
        for ; b != nil; b = b.overflow(t) {
            k := add(unsafe.Pointer(b), dataOffset)
            e := add(k, bucketCnt*uintptr(t.keysize))
            // 遍历 bucket 中的所有 cell
            for i := 0; i < bucketCnt; i, k, e = i+1, add(k, uintptr(t.keysize)), add(e, uintptr(t.elemsize)) {
                top := b.tophash[i]  // 当前cell的tophash
                if isEmpty(top) {
                    // 当前cell为空，即没有key，则标志其为 “搬迁过”，然后继续下一个 cell
                    b.tophash[i] = evacuatedEmpty
                    continue
                }
                // 正常情况下，tophash只能是 evacuatedEmpty 或者 正常的tophash(大于等于minTopHash)
                if top < minTopHash {
                    throw("bad map state")
                }
                k2 := k
                if t.indirectkey() {
                    k2 = *((*unsafe.Pointer)(k2))
                }
                var useY uint8
                if !h.sameSizeGrow() {
                    // 计算如何分流(将这个键值对放到x中还是y中)
                    // 计算方法与前面相同
                    hash := t.hasher(k2, uintptr(h.hash0))
                    // !t.key.equal(k2, k2)这种情况，只能是float的NaN了
                    // 没有协程正在使用map && 不是float的NaN
                    if h.flags&iterator != 0 && !t.reflexivekey() && !t.key.equal(k2, k2) {
                        // 在这种情况下，我们使用 tophash 的低位来作为分流的标准
                        useY = top & 1
                        top = tophash(hash)
                    } else {
                        if hash&newbit != 0 {
                            useY = 1  // 新的位置位于高区间
                        }
                    }
                }

                if evacuatedX+1 != evacuatedY || evacuatedX^1 != evacuatedY {
                    throw("bad evacuatedN")
                }

                b.tophash[i] = evacuatedX + useY // evacuatedX + 1 == evacuatedY
                dst := &xy[useY]                 // 放到高位置还是低位置

                // 是否要放到 overflow 中
                if dst.i == bucketCnt {
                    dst.b = h.newoverflow(t, dst.b)
                    dst.i = 0
                    dst.k = add(unsafe.Pointer(dst.b), dataOffset)
                    dst.e = add(dst.k, bucketCnt*uintptr(t.keysize))
                }
                dst.b.tophash[dst.i&(bucketCnt-1)] = top // mask dst.i as an optimization, to avoid a bounds check
                if t.indirectkey() {
                    *(*unsafe.Pointer)(dst.k) = k2 // copy pointer
                } else {
                    typedmemmove(t.key, dst.k, k) // copy elem
                }
                if t.indirectelem() {
                    *(*unsafe.Pointer)(dst.e) = *(*unsafe.Pointer)(e)
                } else {
                    typedmemmove(t.elem, dst.e, e)
                }
                dst.i++
                // These updates might push these pointers past the end of the
                // key or elem arrays.  That's ok, as we have the overflow pointer
                // at the end of the bucket to protect against pointing past the
                // end of the bucket.
                dst.k = add(dst.k, uintptr(t.keysize))
                dst.e = add(dst.e, uintptr(t.elemsize))
            }
        }
        // 如果没有协程在使用老的 buckets，就把老 buckets 清除掉，帮助gc
        if h.flags&oldIterator == 0 && t.bucket.ptrdata != 0 {
            b := add(h.oldbuckets, oldbucket*uintptr(t.bucketsize))
            // 只清除bucket 的 key,value 部分，保留 top hash 部分，指示搬迁状态
            ptr := add(b, dataOffset)
            n := uintptr(t.bucketsize) - dataOffset
            memclrHasPointers(ptr, n)
        }
    }

    // 最后会调用 advanceEvacuationMark 增加哈希的 nevacuate 计数器，在所有的旧桶都被分流后清空哈希的 oldbuckets 和 oldoverflow 字段
    if oldbucket == h.nevacuate {
        advanceEvacuationMark(h, t, newbit)
    }
}
```

简单总结一下分流规则：

1. 对于等量扩容，从旧的 `bucket` 到新的 `bucket`，数量不变，因此可以按照 `bucket` 一一对应，原来是 0 号，搬过去之后还是 0 号；
2. 对于渐进式扩容，要重新计算 `key` 的 哈希，才能决定落在哪个 `bucket` 。原来只有 `2^B` 个`bucket` ，确定某个 key 位于哪个 `bucket` 需要使用最后`B` 位；现在 `B` 增加了 1，那就应该使用最后的 `B+1` 位，即向前看一位。比如原来的 `B=3`，`key1`和`key2`的哈希后四位分别是 `0x0101` 和 `0x1101`，因为二者的后三位相同，所以会落在同一个 `bucket` 中，现在进行渐进式扩容，需要多看一位，此时`key1`和`key2`的哈希后四位不相同，因为倒数第 4 位有 0 和 1 两种取值，这也就是我们源码中说的 `X` 和 `Y`，`key1`和`key2`也就会落入不同的 `bucket` 中——如果是 0，分配到`X`，如果是 1 ，分配到 `Y`。

还有一种情况是上面函数中第 64 行 `!t.key.equal(k2, k2)`，即相同的 `key` ，对它进行哈希计算，两次结果竟然不相同，这种情况来自于 `math.NaN()`，`NaN` 的意思是 `Not a Number`，在 Go 中是 `float64` 类型(打印出来直接显示 “NaN”)，当使用它作为某个 `map` 的 `key` 时，前后计算出来的哈希是不同的，这样的后果是，我们永远无法通过 GET 操作获取到这个键值对，即使用 `map[math.NaN]` 是取不到想要的结果的，只有在遍历整个 `map` 的时候才会出现。这种情况下，在决定分流到 `X` 还是 `Y` 中时，就只能 使用`tophash`的最低位来决定 这个策略了——如果 tophash 的最低位是 0 ，分配到 X part；如果是 1 ，则分配到 Y part。

> 关于 `NaN`：In [computing](https://en.wikipedia.org/wiki/Computing), **NaN**, standing for **Not a Number**, is a member of a numeric [data type](https://en.wikipedia.org/wiki/Data_type) that can be interpreted as a [value](<https://en.wikipedia.org/wiki/Value_(mathematics)>) that is undefined or unrepresentable, especially in [floating-point arithmetic](https://en.wikipedia.org/wiki/Floating-point_arithmetic).
>
> 在计算机科学中，`NaN` 代表 `Not a Number`，是一个 能够被打印出来的 未定义或者不可预知的 数字类型。
> 我们简单总结一下哈希表的扩容设计和原理，哈希在存储元素过多时会触发扩容操作，每次都会将桶的数量翻倍，整个扩容过程并不是原子的，而是通过 `growWork`增量触发的，在扩容期间访问哈希表时会使用旧桶，向哈希表写入数据时会触发旧桶元素的分流；除了这种正常的扩容之外，为了解决大量写入、删除造成的内存泄漏问题，哈希引入了 `sameSizeGrow(等量扩容)` 这一机制，在出现较多溢出桶时会对哈希进行『内存整理』减少对空间的占用。————[Go 语言设计与实现 3.3 哈希表](https://draveness.me/golang/docs/part2-foundation/ch03-datastructure/golang-hashmap/#%E6%89%A9%E5%AE%B9)

### 5. 删除

Go 语言中删除一个 `map` 中的 `key`，使用的是特定的关键字 `delete(map, key)`。在底层，实际调用的 `/usr/local/go/src/runtime/map.go` 中的 `mapdelete`。这个函数的执行过程和 **写** 过程类似，如果在删除期间当前操作的桶遇到了扩容，就会对该桶进行分流，分流之后找到同种的目标元素完成键值对的删除工作。

### 6. 遍历

理论上`map` 的遍历比较简单——“遍历所有的 `bucket` 以及它后面挂的 `overflow bucket`，然后挨个遍历 `bucket` 中的所有 `cell`。每个 `bucket` 中包含 8 个 `cell`，从有 `key` 的 `cell` 中取出 `key` 和 `value`，这个过程就完成了。” 但实际情况是，当我们在遍历一个处在扩容阶段的 `map` 时，不仅要考虑到已经搬过去的位于 `h.buckets` 的，还要考虑还没有搬的位于 `h.oldbuckets` 中的。

接下来我们还是通过源码的方式逐步探寻 **map 遍历** 的奥秘。

与之相关的函数分别是 `mapiterinit` 和 `mapiternext`，前者会初始化一个迭代器，之后循环调用后者进行迭代。迭代器结构如下：

```go
type hiter struct {
    key         unsafe.Pointer  // key的指针，必须放在第一位，nil表示迭代结束
    elem        unsafe.Pointer  // value指针，必须放在第二位
    t           *maptype        // map中key的类型
    h           *hmap           // 指向map的指针
    buckets     unsafe.Pointer  // 初始化时指向的 bucket
    bptr        *bmap           // 当前遍历到的 map
    overflow    *[]*bmap        // keeps overflow buckets of hmap.buckets alive
    oldoverflow *[]*bmap        // keeps overflow buckets of hmap.oldbuckets alive
    startBucket uintptr         // 起始迭代的 bucket 编号
    offset      uint8           // 遍历时的偏移量(可以理解成遍历开始的 cell 号)
    wrapped     bool            // 是否从头遍历
    B           uint8           // h.B
    i           uint8           // 当前的 cell 编号
    bucket      uintptr         // 当前的 bucket
    checkBucket uintptr         // 因为扩容，需要检查的 bucket
}
```

`mapiterinit` 主要是对 `hiter` 的初始化，需要关注的是这几行：

```go
func mapiterinit(t *maptype, h *hmap, it *hiter) {
    // ...
    // decide where to start
    r := uintptr(fastrand())
    // bucketCntBits=3
    if h.B > 31-bucketCntBits {
        r += uintptr(fastrand()) << 31
    }
    // bucketMask 即 1<<h.B -1
    it.startBucket = r & bucketMask(h.B)
    // bucketCnt=8
    it.offset = uint8(r >> h.B & (bucketCnt - 1))

    // ...
}
```

`r` 是一个随机数，这里假设我们的 `m = make(map[string]int)`， `h.B=2`，即有 `2^2=4` 个桶，可以计算得到 `bucketMask(h.B)=3`，二进制表示为 `0000 0011`，将 `r` 与这个数相与，就能得到 `0~3` 的 `bucket` 序号；同样，第 12 行，7 的二进制表示为 `0000 0111`，将 `r` 右移两位之后，与 7 相与，可以得到 `0~7` 的一个 `cell` 序号。**这就是 `map` 每次遍历的 `key` 都是无序的原因**。

之后，使用这个随机的 `bucket` ，在里面的随机的这个 `cell` 处开始遍历，取出其中的键值对，直到回到这个 `bucket` 。

接下来我们看 `mapiternext` 的细节：

```go
func mapiternext(it *hiter) {
    h := it.h
    if raceenabled {
        callerpc := getcallerpc()
        racereadpc(unsafe.Pointer(h), callerpc, funcPC(mapiternext))
    }
    if h.flags&hashWriting != 0 {
        throw("concurrent map iteration and map write")
    }
    t := it.t
    bucket := it.bucket
    b := it.bptr
    i := it.i
    checkBucket := it.checkBucket

next:
    if b == nil {
        if bucket == it.startBucket && it.wrapped {
            // 回到了最开始遍历的那个 bucket，说明遍历结束了，可以退出迭代了
            it.key = nil
            it.elem = nil
            return
        }
        if h.growing() && it.B == h.B {
            // 如果我们当前遍历的 bucket 对应的原来的老的 bucket 的状态位显示为 “未搬迁”，则不再遍历当前的 bucket 而去遍历老的 bucket
            oldbucket := bucket & it.h.oldbucketmask()
            b = (*bmap)(add(h.oldbuckets, oldbucket*uintptr(t.bucketsize)))
            if !evacuated(b) {
                checkBucket = bucket
            } else {
                b = (*bmap)(add(it.buckets, bucket*uintptr(t.bucketsize)))
                checkBucket = noCheck
            }
        } else {
            b = (*bmap)(add(it.buckets, bucket*uintptr(t.bucketsize)))
            checkBucket = noCheck
        }
        bucket++
        if bucket == bucketShift(it.B) {
            bucket = 0
            it.wrapped = true
        }
        i = 0
    }
    for ; i < bucketCnt; i++ {
        offi := (i + it.offset) & (bucketCnt - 1)
        // 当前 cell 是空的，继续下一个 cell
        if isEmpty(b.tophash[offi]) || b.tophash[offi] == evacuatedEmpty {
            continue
        }
        k := add(unsafe.Pointer(b), dataOffset+uintptr(offi)*uintptr(t.keysize))
        if t.indirectkey() {
            k = *((*unsafe.Pointer)(k))
        }
        e := add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+uintptr(offi)*uintptr(t.elemsize))
        if checkBucket != noCheck && !h.sameSizeGrow() {
        // 正好遇上扩容但是扩容还没完成，如果我们当前遍历的 bucket 对应的老 bucket还没有进行迁移，那么需要去遍历未搬迁的老的 bucket，但是！并不是遍历对应的全部的老的 bucket，而是只遍历 分流后会落在当前 bucket 的那部分键值对
            if t.reflexivekey() || t.key.equal(k, k) {
                // 对于老 bucket 中不会分流到这个 bucket 的键值对，直接跳过
                hash := t.hasher(k, uintptr(h.hash0))
                if hash&bucketMask(it.B) != checkBucket {
                continue
                }
            } else {
                // 处理 math.NaN 情况，还是一样，看最低位来决定是不是落在当前这个 bucket
                if checkBucket>>(it.B-1) != uintptr(b.tophash[offi]&1) {
                    continue
                }
            }
        }
        if (b.tophash[offi] != evacuatedX && b.tophash[offi] != evacuatedY) || !(t.reflexivekey() || t.key.equal(k, k)) {
            // 对于 math.NaN 情况，我们只能通过遍历找到，对它的增删改查都是不可能的(这也是比较幸运的一件事，最起码能访问到，否则那真就成了“幽灵”了——占用空间又无可奈何，而且还能同一个 key 无限制地添加)
            it.key = k
            if t.indirectelem() {
                e = *((*unsafe.Pointer)(e))
            }
            it.elem = e
        } else {
            // 开始迭代的时候，已经完成了扩容。此时 math.NaN 已经被放置到了别的 bucket 中，这种情况下只需要处置已经被 更新、删除或者删除后重新插入的情况。需要注意的是那些在 equal() 函数中判断为真的但是实际上他们的 key 不相同的情况，比如 +0.0 vs -0.0
            rk, re := mapaccessK(t, h, k)
            if rk == nil {
                continue // key 已经被删除
            }
            it.key = rk
            it.elem = re
        }
        it.bucket = bucket
        if it.bptr != b { // avoid unnecessary write barrier; see issue 14921
            it.bptr = b
        }
        it.i = i + 1
        it.checkBucket = checkBucket
        return
    }
    b = b.overflow(t)
    i = 0
    goto next
}
```

在 [码农桃花源 深度解密 Go 语言之 map](https://mp.weixin.qq.com/s?__biz=MjM5MDUwNTQwMQ==&mid=2257483772&idx=1&sn=a6462bc41ec70edf5d60df37a6d4e966&scene=19#wechat_redirect) 中 **map 遍历** 一节，作者举了一个非常通俗易懂的例子，非常推荐，建议去看一下加深理解。

## 四、总结

这是我第一次非常深入地看源码，也领会到了**一切疑难杂症都会在源码面前原形毕露**。`map` 操作的核心，就在于如何在各种情况下定位到具体的 `key`，搞清楚了这一点，其他问题看源码会更清晰。

Go 语言中，哈希表的实现采用的哈希查找表，使用拉链法解决哈希冲突。有**空间换时间**的思想体现(不同的 key 落到不同的 bucket，即定位`bucket`的过程)，也有 **时间换空间** 思想的体现(在一个 `bucket` 中，采用遍历的方式寻找 `key` 而不是再使用哈希)，同时渐进式扩容和等量扩容的思想也值得我们学习。
