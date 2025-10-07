---
title: "最小堆以及优先级队列的Golang实现"
date: 2021-05-13T21:08:09+08:00
draft: false

author: JemmyHu(hujm20151021@gmail.com)
toc: true
mathjax: true
categories: [技术博客, 技术细节, 优秀数据结构]
tags: [Golang, 最小堆, 优先级队列]
comment: true
cover:
  image: https://pic.downk.cc/item/5f77e088160a154a67ede68f.png
summary:
---

## 前言

[堆](https://zh.wikipedia.org/wiki/%E5%A0%86%E7%A9%8D)，是计算机科学中的一种特别的完全二叉树。若父节点的值恒小于等于子节点的值，此堆称为**最小堆（min heap）**；反之，若母节点的值恒大于等于子节点的值，此堆称为**最大堆（max heap）**。在堆中最顶端的那一个节点，称作 **根节点（root node）**，根节点本身没有 **父节点（parent node）**。堆通常是一个可以被看做一棵树的数组对象。在队列中，调度程序反复提取队列中第一个作业并运行，因为实际情况中某些时间较短的任务将等待很长时间才能结束，或者某些不短小，但具有重要性的作业，同样应当具有优先权。堆即为解决此类问题设计的一种数据结构。

[优先级队列](https://zh.wikipedia.org/wiki/%E5%84%AA%E5%85%88%E4%BD%87%E5%88%97) 是计算机科学中的一类抽象数据类型。优先队列中的每个元素都有各自的优先级，优先级最高的元素最先得到服务；优先级相同的元素按照其在优先队列中的顺序得到服务。**优先队列往往用堆来实现**。

## `Golang`实现一：根据原理简单实现

```golang
package minheap

import (
    "container/heap"
    "fmt"
    "math"

    "github.com/pkg/errors"
)

/*
* @CreateTime: 2021/7/6 21:57
* @Author: hujiaming
* @Description: Golang实现最小堆
 */

var ErrMinHeapEmpty = errors.New("minHeap is empty")

const HeapHeadTag int64 = math.MinInt64

type MinHeap struct {
    elements []int64
}

// NewMinHeap 创建一个最小堆实例
func NewMinHeap() *MinHeap {
    return &MinHeap{elements: []int64{HeapHeadTag}}
}

/*
Add 将一个元素添加到最小堆中，并且添加后要使其满足最小堆的特性
首先将该元素插入到数组最后，然后对这最后一个元素进行 “上浮” 操作：
该元素与父元素进行大小比较，如果小于父元素，则和父元素交换位置，如此循环，直到 到达堆顶 或 子元素小于父元素。
*/
func (mh *MinHeap) Add(v int64) {
    // 1. 先将元素插在数组最后面
    mh.elements = append(mh.elements, v)
    // 2. 将最后一个元素上浮，使其符合最小堆的性质。其实是为 v 找位置
    i := len(mh.elements) - 1
    for ; mh.elements[i/2] > v; i /= 2 {
        mh.elements[i] = mh.elements[i/2]
    }
    mh.elements[i] = v
}

/*
PopMin 弹出堆中最小的元素
对最小堆而言，移除元素，只能移除堆顶(最小值)的元素。
首先，移除堆顶元素，然后将最后一个元素放在堆顶，之后对这第一个元素进行 “下沉” 操作：
将此元素与两个子节点元素比较，如果当前结点大于两个子节点，则与较小的子节点交换位置，如此循环，直到 到达叶子结点 或 小于较小子节点。
*/
func (mh *MinHeap) PopMin() (int64, error) {
    if mh.IsEmpty() {
        return 0, ErrMinHeapEmpty
    }
    res := mh.elements[1]
    last := mh.elements[len(mh.elements)-1]
    // idx 表示最后一个元素应该在的位置
    var idx int
    for idx = 1; idx*2 < len(mh.elements); {
        // 找出子节点中较小的元素的 index
        minChildIdx := idx * 2
        if minChildIdx < len(mh.elements)-1 && mh.elements[minChildIdx+1] < mh.elements[minChildIdx] {
            minChildIdx++
        }
        // 当前结点 大于 较小子节点，和这个较小子节点交换位置，继续循环
        if last > mh.elements[minChildIdx] {
            mh.elements[idx] = mh.elements[minChildIdx]
            idx = minChildIdx
            continue
        }
        break
    }
    mh.elements[idx] = last
    mh.elements = mh.elements[:len(mh.elements)-1]

    return res, nil
}

// PeekHead 只返回堆顶元素(最小值)，不进行下沉操作
func (mh *MinHeap) PeekHead() (int64, error) {
    if mh.IsEmpty() {
        return 0, ErrMinHeapEmpty
    }
    return mh.elements[1], nil
}

// IsEmpty 最小堆是否是空的
func (mh *MinHeap) IsEmpty() bool {
    if len(mh.elements) == 0 || (len(mh.elements) == 1 && mh.elements[0] == HeapHeadTag) {
        return true
    }
    return false
}

// Length 返回最小堆中的元素个数
func (mh *MinHeap) Length() int {
    return len(mh.elements) - 1
}

// Print 打印代表最小堆的数组
func (mh *MinHeap) Print() {
    fmt.Println(mh.elements[1:])
}
```

`Test` 如下：

```golang
func TestMinHeap(t *testing.T) {
    mh := NewMinHeap()
    mh.Add(4)
    mh.Add(2)
    mh.Add(7)
    mh.Add(9)
    mh.Add(1)
    mh.Add(5)
    mh.Add(10)
    mh.Add(3)
    mh.Add(2)
    mh.Print()
    for !mh.IsEmpty() {
        fmt.Println(mh.PopMin())
    }
    assert.Equal(t, mh.Length(), 0)
}

// 输出
/*

[1 2 5 2 4 7 10 9 3]
1 <nil>
2 <nil>
2 <nil>
3 <nil>
4 <nil>
5 <nil>
7 <nil>
9 <nil>
10 <nil>

*/
```

## `Golang` 实现二：实现标准库 `heap.Interface` 接口

先看下标准库中的 `Interface`，位置在 `container/heap/heap.go`：

```golang
// The Interface type describes the requirements
// for a type using the routines in this package.
// Any type that implements it may be used as a
// min-heap with the following invariants (established after
// Init has been called or if the data is empty or sorted):
//
// !h.Less(j, i) for 0 <= i < h.Len() and 2*i+1 <= j <= 2*i+2 and j < h.Len()
//
// Note that Push and Pop in this interface are for package heap's
// implementation to call. To add and remove things from the heap,
// use heap.Push and heap.Pop.
type Interface interface {
    sort.Interface
    Push(x interface{}) // add x as element Len()
    Pop() interface{}   // remove and return element Len() - 1.
}

// An implementation of Interface can be sorted by the routines in this package.
// The methods refer to elements of the underlying collection by integer index.
type Interface interface {
    // Len is the number of elements in the collection.
    Len() int

    // Less reports whether the element with index i
    // must sort before the element with index j.
    //
    // If both Less(i, j) and Less(j, i) are false,
    // then the elements at index i and j are considered equal.
    // Sort may place equal elements in any order in the final result,
    // while Stable preserves the original input order of equal elements.
    //
    // Less must describe a transitive ordering:
    //  - if both Less(i, j) and Less(j, k) are true, then Less(i, k) must be true as well.
    //  - if both Less(i, j) and Less(j, k) are false, then Less(i, k) must be false as well.
    //
    // Note that floating-point comparison (the < operator on float32 or float64 values)
    // is not a transitive ordering when not-a-number (NaN) values are involved.
    // See Float64Slice.Less for a correct implementation for floating-point values.
    Less(i, j int) bool

    // Swap swaps the elements with indexes i and j.
    Swap(i, j int)
}
```

我们以此为基础，实现一个 **优先级队列**:

```golang
package priorityqueen


type Item struct {
    value    int64 // 实际值
    priority int64 // 优先级
    index    int   // 当前 item 在数组中的 index
}

// PriorityQueen 表示优先级队列
type PriorityQueen []*Item

func (mh2 PriorityQueen) Len() int {
    return len(mh2)
}

func (mh2 PriorityQueen) Less(i, j int) bool {
    return mh2[i].priority < mh2[j].priority
}

func (mh2 PriorityQueen) Swap(i, j int) {
    mh2[i], mh2[j] = mh2[j], mh2[i]
    mh2[i].index = i
    mh2[j].index = j
}

// Push 将 x 添加到数组最后
func (mh2 *PriorityQueen) Push(x interface{}) {
    l := len(*mh2)
    c := cap(*mh2)
    if l+1 > c {
        cmh2 := make([]*Item, l, c/2)
        copy(*mh2, cmh2)
        *mh2 = cmh2
    }
    *mh2 = (*mh2)[:l+1]
    item := (x).(*Item)
    item.index = l
    (*mh2)[l] = item
}

// Pop 返回数组最后一个元素
func (mh2 *PriorityQueen) Pop() interface{} {
    l := len(*mh2)
    c := cap(*mh2)
    if l < c/2 && c > 25 {
        cmh2 := make([]*Item, l, c/2)
        copy(cmh2, *mh2)
        *mh2 = cmh2
    }
    item := (*mh2)[l-1]
    item.index = -1 // for safety
    *mh2 = (*mh2)[:l-1]
    return item
}

// PopHead 弹出堆顶元素
func (mh2 *PriorityQueen) PopHead() *Item {
    if mh2.Len() == 0 {
        return nil
    }
    item := (*mh2)[0]

    heap.Remove(mh2, 0)

    return item
}

// PopWithPriority 弹出优先级小于 maxP 的堆顶元素，如果没有，返回 nil 和 当前堆顶和maxP的距离
func (mh2 *PriorityQueen) PopWithPriority(maxP int64) (*Item, int64) {
    if mh2.Len() == 0 {
        return nil, 0
    }
    item := (*mh2)[0]
    if item.priority > maxP {
        return nil, item.priority - maxP
    }

    heap.Remove(mh2, 0)

    return item, 0
}

// PeekHead 显示堆顶元素
func (mh2 *PriorityQueen) PeekHead() *Item {
    if mh2.Len() == 0 {
        return nil
    }
    heap.Init(mh2)
    item := (*mh2)[0]
    return item
}
```

测试一下：

```golang
func TestPriorityQueen(t *testing.T) {
    items := make([]*Item, 0)
    rand.Seed(time.Now().UnixNano())

    for i := 0; i < 10; i++ {
        v := rand.Int63n(100)
        items = append(items, &Item{
            value:    v,
            priority: v,
            index:    i,
        })
    }
    q := PriorityQueen(items)
    heap.Init(&q)

    fmt.Println(q.PeekHead())

    maxP := int64(50)
    for _, i := range q {
        if i.priority < maxP {
            fmt.Println(fmt.Sprintf("p: %d, v: %d", i.priority, i.value))
        }
    }

    fmt.Println("====")
    for i := 0; i < 10; i++ {
        item, _ := q.PopWithPriority(maxP)
        if item != nil {
            fmt.Println(item)
        }
    }

    fmt.Println("====")
    for {
        item := q.PopHead()
        if item == nil {
            break
        }
        fmt.Println(item)
    }
}

// 输出
/*

&{5 5 0}
p: 5, v: 5
p: 11, v: 11
p: 6, v: 6
p: 33, v: 33
====
&{5 5 -1}
&{6 6 -1}
&{11 11 -1}
&{33 33 -1}
&{50 50 -1}
====
&{52 52 -1}
&{73 73 -1}
&{85 85 -1}
&{97 97 -1}
&{99 99 -1}

*/
```

## Golang 标准库 `heap.Interface` 源码解析

整个包的实现非常简洁，加上注释以及空行，整个文件才只有120 行：

```go
// Copyright 2009 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Package heap provides heap operations for any type that implements
// heap.Interface. A heap is a tree with the property that each node is the
// minimum-valued node in its subtree.
//
// The minimum element in the tree is the root, at index 0.
//
// A heap is a common way to implement a priority queue. To build a priority
// queue, implement the Heap interface with the (negative) priority as the
// ordering for the Less method, so Push adds items while Pop removes the
// highest-priority item from the queue. The Examples include such an
// implementation; the file example_pq_test.go has the complete source.
//
package heap

import "sort"

// The Interface type describes the requirements
// for a type using the routines in this package.
// Any type that implements it may be used as a
// min-heap with the following invariants (established after
// Init has been called or if the data is empty or sorted):
//
// !h.Less(j, i) for 0 <= i < h.Len() and 2*i+1 <= j <= 2*i+2 and j < h.Len()
//
// Note that Push and Pop in this interface are for package heap's
// implementation to call. To add and remove things from the heap,
// use heap.Push and heap.Pop.
type Interface interface {
    sort.Interface
    Push(x interface{}) // add x as element Len()
    Pop() interface{}   // remove and return element Len() - 1.
}

// Init establishes the heap invariants required by the other routines in this package.
// Init is idempotent with respect to the heap invariants
// and may be called whenever the heap invariants may have been invalidated.
// The complexity is O(n) where n = h.Len().
func Init(h Interface) {
    // heapify
    n := h.Len()
        // (n/2 - 1) 处的结点是最后一棵子树(没有孩子结点)的根节点
    for i := n/2 - 1; i >= 0; i-- {
        down(h, i, n)
    }
}

// Push pushes the element x onto the heap.
// The complexity is O(log n) where n = h.Len().
func Push(h Interface, x interface{}) {
    h.Push(x)
    up(h, h.Len()-1)
}

// Pop removes and returns the minimum element (according to Less) from the heap.
// The complexity is O(log n) where n = h.Len().
// Pop is equivalent to Remove(h, 0).
func Pop(h Interface) interface{} {
    n := h.Len() - 1
    h.Swap(0, n)
    down(h, 0, n)
    return h.Pop()
}

// Remove removes and returns the element at index i from the heap.
// The complexity is O(log n) where n = h.Len().
func Remove(h Interface, i int) interface{} {
    n := h.Len() - 1
    if n != i {
        h.Swap(i, n)
        if !down(h, i, n) {
            up(h, i)
        }
    }
    return h.Pop()
}

// Fix re-establishes the heap ordering after the element at index i has changed its value.
// Changing the value of the element at index i and then calling Fix is equivalent to,
// but less expensive than, calling Remove(h, i) followed by a Push of the new value.
// The complexity is O(log n) where n = h.Len().
func Fix(h Interface, i int) {
    if !down(h, i, h.Len()) {
        up(h, i)
    }
}

func up(h Interface, j int) {
    for {
        i := (j - 1) / 2 // parent
        if i == j || !h.Less(j, i) {
            break
        }
        h.Swap(i, j)
        j = i
    }
}

func down(h Interface, i0, n int) bool {
    i := i0
    for {
        j1 := 2*i + 1
        if j1 >= n || j1 < 0 { // j1 < 0 after int overflow
            break
        }
        j := j1 // left child
        if j2 := j1 + 1; j2 < n && h.Less(j2, j1) {
            j = j2 // = 2*i + 2  // right child
        }
        if !h.Less(j, i) {
            break
        }
        h.Swap(i, j)
        i = j
    }
    return i > i0
}
```

我们关注其中几个核心实现：

- `down(h Interface, idx, heapLen int)` 下沉操作：
首先，移除堆顶元素，然后将最后一个元素放在堆顶，之后对这第一个元素进行 “下沉” 操作：
将此元素与两个子节点元素比较，如果当前结点大于两个子节点，则与较小的子节点交换位置，如此循环，直到 到达叶子结点 或 小于较小子节点。
为什么元素 i 比它的两个子节点都小，就可以跳出循环，不再继续下去呢？这是由于，在 `Init` 函数中，**第一个开始 `down` 的元素是第 `n/2 - 1` 个，可以保证总是从最后一棵子树开始 `down`**，因此可以保证 `Init->down` 时，如果元素 `i` 比它的两个子节点都小，那么该元素对应的子树，就是最小堆。
![image](https://image.hujm.net/124694449-dc665a00-df13-11eb-8e72-1cbef91adac6.png)

- `up(h Interface, curIdx int)` 上浮操作：
主要用在 `Push` 中，当我们向最小堆插入一个元素时，现将其插入到数组最后，之后进行上浮操作，此时的 `curIdx` 就是数组最后一个元素的 `index`，即 `h.Len() - 1`。当前元素与其父元素进行比较，如果当前元素小于父元素，则与父元素交换位置，如此往复，直到堆顶或者当前元素大于父元素。
