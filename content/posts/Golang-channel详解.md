---
title: "Golang Channel详解"
date: 2021-04-09T11:57:42+08:00
draft: false
author: JemmyHu(hujm20151021@gmail.com)
toc: true
mathjax: true
summary:
categories: [技术博客, 技术细节, Golang]
tags: [Golang, channel]
comment: true
cover:
  image: https://pic.downk.cc/item/5f61dc63160a154a6777224d.png
---

## 一、原理

### 0. 简介

channel 分为有缓冲和无缓冲，或者阻塞和非阻塞，主要区别就在于是否有 `容量capacity`。
在 `runtime` 中是通过 `hchan` 这个结构体来表示的，它里面的主要成员可以理解成包含两个大部分：环形队列相关 和 sudog等待队列 相关。
对于有缓冲的 channel，会设置环形队列相关的参数，如已有的元素数量、容量、指向队列的指针等；
等待队列有发送等待队列和接受等待队列，他们分别在发送时 channel 已满、接收时 channel 为空的情况下，会将当前 goroutine 打包成一个 sudog 结构，添加到对应的队列中，直到条件符合时再被唤醒工作。

```go
type hchan struct {
  qcount   uint           // 环形队列中已经有的元素个数
  dataqsiz uint           // 环形队列容量，就是用户创建时指定的 capacity
  buf      unsafe.Pointer // 环形队列所在的地址
  elemsize uint16         // channal 中元素类型的大小
  closed   uint32         // channel 是否关闭
  elemtype *_type         // channel 元素类型
  sendx    uint           // 环形队列中已经发送的 index
  recvx    uint           // 环形队列中已经接受的 index
  recvq    waitq          // 等待接受 channel 中消息的 goroutine 队列
  sendq    waitq          // 等待向 channel 中发送消息的 goroutine 队列

  lock mutex
}
```

### 1. 用法以及常见问题汇总

- 已经关闭的 channel，再次关闭会 panic
- 向已经关闭的 channel 发送数据会造成 panic
- 如果从 channel 中取出元素的方式是 `for-range`，则在 channel 关闭时会自动退出循环

```go
func main() {
    ch := make(chan int, 10)
    go func() {
        for i := 0; i < 10; i++ {
            ch <- i
        }
        // 注意这里的 close，如果没有，将会出现死锁 panic
        close(ch)
    }()
    for j := range ch {
        fmt.Println(j)
    }
}
```

- close 一个 channel 时，如果还有 sender goroutine 挂在 channel 的发送队列中，则会引起 panic。首先 `close` 会唤醒所有在此 channel 等待队列中的 goroutine，使其状态变为 `Grunable`，再看下文 3 中的 `sendchan` 源码就知道，当 goroutine 被唤醒之后，还会去检查 channel 是否已经被关闭，如果被关闭则会 panic。

- 从已经 close 的 channel 中取值(说明已经正常关闭，channel 是空的)，会返回 channel 元素的零值。区分零值还是真实值，可以使用 `comma, ok` 的语法：

```go
x, ok := <- ch
if !ok{
    // channel 已经被关闭
    // .....
}
```

> If the receiving goroutine queue of the channel is not empty, in which case the value buffer of the channel must be empty, all the goroutines in the receiving goroutine queue of the channel will be unshifted one by one, each of them will receive a zero value of the element type of the channel and be resumed to running state.

- 没有通过 `make` 来初始化的 channel 被称为 `nil channel`，关闭一个 `nil channel` 会直接 panic

### 2. 创建 channel

```go
// 初始化 channel    
func makechan(t *chantype, size int) *hchan {
    elem := t.elem

    // compiler checks this but be safe.
    if elem.size >= 1<<16 {
        throw("makechan: invalid channel element type")
    }
    if hchanSize%maxAlign != 0 || elem.align > maxAlign {
        throw("makechan: bad alignment")
    }

    mem, overflow := math.MulUintptr(elem.size, uintptr(size))
    if overflow || mem > maxAlloc-hchanSize || size < 0 {
        panic(plainError("makechan: size out of range"))
    }

    // Hchan does not contain pointers interesting for GC when elements stored in buf do not contain pointers.
    // buf points into the same allocation, elemtype is persistent.
    // SudoG's are referenced from their owning thread so they can't be collected.
    // 如果 hchan 中的元素不包含指针，那么也就不需要 GC
    var c *hchan
    switch {
    case mem == 0:
        /*
            channel 中缓冲区大小是 0(ch := make(chan int, 0)) 或者 元素类型的大小是 0(ch := make(chan struct{}))
            此时所需的空间只有 hchan 这一个元素的
        */
        // Queue or element size is zero.
        c = (*hchan)(mallocgc(hchanSize, nil, true))
        // Race detector uses this location for synchronization.
        c.buf = c.raceaddr()
    case elem.ptrdata == 0:
        /*
            channel 中元素的类型不是指针。
            此时所需要的空间除了 hchan 的，还有对应元素的：uintptr(size)*elem.size + hchanSize
            因为不是指针，GC 也不会对channel中的元素进行 scan
        */
        // Elements do not contain pointers.
        // Allocate hchan and buf in one call.
        c = (*hchan)(mallocgc(hchanSize+mem, nil, true))
        c.buf = add(unsafe.Pointer(c), hchanSize)
    default:
        /*
            channel 中的元素包含指针。
            注意，这里进行了两次空间分配，一次是给 hchan，第二次是给 channel 中的元素
        */
        // Elements contain pointers.
        c = new(hchan)
        c.buf = mallocgc(mem, elem, true)
    }

    c.elemsize = uint16(elem.size)
    c.elemtype = elem
    c.dataqsiz = uint(size)
    lockInit(&c.lock, lockRankHchan)

    if debugChan {
        print("makechan: chan=", c, "; elemsize=", elem.size, "; dataqsiz=", size, "\n")
    }
    return c
}
```

### 3.  向 channel 发送

```go

// select {case <-xxx} 的入口
func selectnbsend(c *hchan, elem unsafe.Pointer) (selected bool) {
    return chansend(c, elem, false, getcallerpc())
}

// entry point for c <- x from compiled code
//go:nosplit
func chansend1(c *hchan, elem unsafe.Pointer) {
    chansend(c, elem, true, getcallerpc())
}

 // 向一个 channel 发送数据的具体实现
 // c 就是 channel 实体，ep 表示要发送的数据，block 表示是否阻塞(正常业务逻辑中是 true，如果是 select 则是 false)
func chansend(c *hchan, ep unsafe.Pointer, block bool, callerpc uintptr) bool {
    /*
        应用层的 channel 是空的，如 
        var ch chan int
        ch <- 1
        如果非阻塞，则直接返回；
        如果阻塞，也就是向一个 nil channel 发送数据，那么将永久阻塞下去
        需要注意的是，空的channel 和 已经关闭的channel是不同的。向空 channel 发送将永久阻塞，向 closed channel 发送将 panic。
    */
    if c == nil {
        if !block {
            return false
        }
        gopark(nil, nil, waitReasonChanSendNilChan, traceEvGoStop, 2)
        throw("unreachable")
    }

    if debugChan {
        print("chansend: chan=", c, "\n")
    }

    // 数据竞争相关的检测，后面专门说明
    if raceenabled {
        racereadpc(c.raceaddr(), callerpc, funcPC(chansend))
    }

    // Fast path: check for failed non-blocking operation without acquiring the lock.
    //
    // After observing that the channel is not closed, we observe that the channel is
    // not ready for sending. Each of these observations is a single word-sized read
    // (first c.closed and second full()).
    // Because a closed channel cannot transition from 'ready for sending' to
    // 'not ready for sending', even if the channel is closed between the two observations,
    // they imply a moment between the two when the channel was both not yet closed
    // and not ready for sending. We behave as if we observed the channel at that moment,
    // and report that the send cannot proceed.
    //
    // It is okay if the reads are reordered here: if we observe that the channel is not
    // ready for sending and then observe that it is not closed, that implies that the
    // channel wasn't closed during the first observation. However, nothing here
    // guarantees forward progress. We rely on the side effects of lock release in
    // chanrecv() and closechan() to update this thread's view of c.closed and full().
    /*
        这里的 FastPath 其实是对 非阻塞channel(select) 操作判断的一种优化：已经要求不要在 channel 上发生阻塞，
        那么这里迅速做一个判断，“能失败则立刻失败”——如果 非阻塞 && 未关闭 && 已经满了，那就不往后面走了。

        // 检查 channel 是否已经满了
        func full(c *hchan) bool {
            // 无缓冲的 channel
            if c.dataqsiz == 0 {
                // 如果等待队列中有 goroutine 等待，那么就返回 channel 未满，可以进行后续的处理
                return c.recvq.first == nil
            }
            // 有缓冲的 channel，看环形链表中的元素数量是否已经到达容量
            return c.qcount == c.dataqsiz
        }
        如何理解这个 full？
        答：For a zero-capacity (unbuffered) channel, it is always in both full and empty status.
    */
    if !block && c.closed == 0 && full(c) {
        return false
    }

    var t0 int64
    if blockprofilerate > 0 {
        t0 = cputicks()
    }

    lock(&c.lock)

    // 向一个已经关闭的 channel 发送数据，会造成 panic
    if c.closed != 0 {
        unlock(&c.lock)
        panic(plainError("send on closed channel"))
    }

    if sg := c.recvq.dequeue(); sg != nil {
        // Found a waiting receiver. We pass the value we want to send
        // directly to the receiver, bypassing the channel buffer (if any).
        /*
            这里也是一个 FastPath：
               通常情况下往一个 channel 中发送数据，会先将数据复制到环形链表中，然后
            等待接受的 goroutine 来取，再讲数据从唤醒链表中拷贝到 goroutine 中。
               但是考虑一种情况，等待接收的 goroutine 早就在等了(等待队列不为空)，
            这个时候发送过来一个数据，就没必要再先放进 buffer、再拷贝给等待 goroutine 了，
            直接将数据从发送 goroutine 的栈拷贝到接受者 goroutine 的栈中，节省资源。
        */
        send(c, sg, ep, func() { unlock(&c.lock) }, 3)
        return true
    }

    if c.qcount < c.dataqsiz {
        // Space is available in the channel buffer. Enqueue the element to send.
        /*
            如果是有缓冲的 channel 并且 buffer 中空间足够，那么就将数据拷贝到 buffer 中。
            同时更新 
        */ 
        qp := chanbuf(c, c.sendx)
        if raceenabled {
            racenotify(c, c.sendx, nil)
        }
        // 将数据从发送 goroutine 拷贝到 buffer 中
        typedmemmove(c.elemtype, qp, ep)
        // 发送 index++
        c.sendx++
        if c.sendx == c.dataqsiz {
            c.sendx = 0
        }
        // buffer 中 已有元素数量++
        c.qcount++
        unlock(&c.lock)
        return true
    }

    // 如果是非阻塞的 channel(select)，发送的工作已经走完了，可以返回了，后面的都是阻塞 channel 要做的事
    if !block {
        unlock(&c.lock)
        return false
    }

    // Block on the channel. Some receiver will complete our operation for us.
    // 在 channel 上阻塞，receiver 会帮我们完成后续的工作
    // 将当前的发送 goroutine 打包成一个 sudog 结构
    gp := getg()
    mysg := acquireSudog()
    mysg.releasetime = 0
    if t0 != 0 {
        mysg.releasetime = -1
    }
    // No stack splits between assigning elem and enqueuing mysg
    // on gp.waiting where copystack can find it.
    mysg.elem = ep
    mysg.waitlink = nil
    mysg.g = gp
    mysg.isSelect = false
    mysg.c = c
    gp.waiting = mysg
    gp.param = nil

    // 将打包好的 sudog 入队到 channel 的 sendq(发送队列)中
    c.sendq.enqueue(mysg)
    // Signal to anyone trying to shrink our stack that we're about
    // to park on a channel. The window between when this G's status
    // changes and when we set gp.activeStackChans is not safe for
    // stack shrinking.
    // 将这个发送 g 的状态改变：Grunning -> Gwaiting，之后进入休眠
    atomic.Store8(&gp.parkingOnChan, 1)
    gopark(chanparkcommit, unsafe.Pointer(&c.lock), waitReasonChanSend, traceEvGoBlockSend, 2)
    // Ensure the value being sent is kept alive until the
    // receiver copies it out. The sudog has a pointer to the
    // stack object, but sudogs aren't considered as roots of the
    // stack tracer.
    KeepAlive(ep)

    // 后面的是当前 goroutine 被唤醒后的逻辑
    // 醒来后检查一下状态，才会返回成功

    // someone woke us up.
    if mysg != gp.waiting {
        throw("G waiting list is corrupted")
    }
    gp.waiting = nil
    gp.activeStackChans = false
    closed := !mysg.success
    gp.param = nil
    if mysg.releasetime > 0 {
        blockevent(mysg.releasetime-t0, 2)
    }
    mysg.c = nil
    releaseSudog(mysg)
    if closed {
        if c.closed == 0 {
            throw("chansend: spurious wakeup")
        }
        // 醒来后发现 channel 已经被关闭了，直接 panic
        panic(plainError("send on closed channel"))
    }
    return true
}
```

### 4. 从 channel 中接收

```go
func selectnbrecv(elem unsafe.Pointer, c *hchan) (selected bool) {
    selected, _ = chanrecv(c, elem, false)
    return
}

func selectnbrecv2(elem unsafe.Pointer, received *bool, c *hchan) (selected bool) {
    // TODO(khr): just return 2 values from this function, now that it is in Go.
    selected, *received = chanrecv(c, elem, false)
    return
}

// entry points for <- c from compiled code
//go:nosplit
func chanrecv1(c *hchan, elem unsafe.Pointer) {
    chanrecv(c, elem, true)
}

//go:nosplit
func chanrecv2(c *hchan, elem unsafe.Pointer) (received bool) {
    _, received = chanrecv(c, elem, true)
    return
}

// chanrecv receives on channel c and writes the received data to ep.
// ep may be nil, in which case received data is ignored.
// If block == false and no elements are available, returns (false, false).
// Otherwise, if c is closed, zeros *ep and returns (true, false).
// Otherwise, fills in *ep with an element and returns (true, true).
// A non-nil ep must point to the heap or the caller's stack.
// 从 hchan 中接收数据，并将数据拷贝到 ep 对应的空间中。ep 可以是 nil，这种情况下数据会被丢弃；
// 如果 ep 不为 nil，那么必须指向 堆 或者 调用者g的栈地址
// 这里的返回值 selected 表示是否被 select 到，received 表示是否成功接收到数据
func chanrecv(c *hchan, ep unsafe.Pointer, block bool) (selected, received bool) {
    // raceenabled: don't need to check ep, as it is always on the stack
    // or is new memory allocated by reflect.

    if debugChan {
        print("chanrecv: chan=", c, "\n")
    }

    // 从一个阻塞的 nil channel 中接收数据，则会永久阻塞
    if c == nil {
        if !block {
            return
        }
        // 这种情况其实就是 goroutine 泄露
        gopark(nil, nil, waitReasonChanReceiveNilChan, traceEvGoStop, 2)
        throw("unreachable")
    }

    // Fast path: check for failed non-blocking operation without acquiring the lock.
    // FastPath: 如果不阻塞并且没有内容可接收，直接返回 false false
    if !block && empty(c) {
        // After observing that the channel is not ready for receiving, we observe whether the
        // channel is closed.
        //
        // Reordering of these checks could lead to incorrect behavior when racing with a close.
        // For example, if the channel was open and not empty, was closed, and then drained,
        // reordered reads could incorrectly indicate "open and empty". To prevent reordering,
        // we use atomic loads for both checks, and rely on emptying and closing to happen in
        // separate critical sections under the same lock.  This assumption fails when closing
        // an unbuffered channel with a blocked send, but that is an error condition anyway.
        if atomic.Load(&c.closed) == 0 {
            // Because a channel cannot be reopened, the later observation of the channel
            // being not closed implies that it was also not closed at the moment of the
            // first observation. We behave as if we observed the channel at that moment
            // and report that the receive cannot proceed.
            return
        }
        // The channel is irreversibly closed. Re-check whether the channel has any pending data
        // to receive, which could have arrived between the empty and closed checks above.
        // Sequential consistency is also required here, when racing with such a send.
        // 走到这里，说明 channel 是非阻塞的，并且已经关闭了，而且 channel 中没有数据留下，此时会返回对应值的零值
        if empty(c) {
            // The channel is irreversibly closed and empty.
            if raceenabled {
                raceacquire(c.raceaddr())
            }
            if ep != nil {
                typedmemclr(c.elemtype, ep)
            }
            return true, false
        }
    }

    var t0 int64
    if blockprofilerate > 0 {
        t0 = cputicks()
    }

    lock(&c.lock)

    // 当前 channel 中没有数据可读，直接返回
    if c.closed != 0 && c.qcount == 0 {
        if raceenabled {
            raceacquire(c.raceaddr())
        }
        unlock(&c.lock)
        if ep != nil {
            // 将 ep 设置成对应元素的零值
            typedmemclr(c.elemtype, ep)
        }
        return true, false
    }

    if sg := c.sendq.dequeue(); sg != nil {
        // Found a waiting sender. If buffer is size 0, receive value
        // directly from sender. Otherwise, receive from head of queue
        // and add sender's value to the tail of the queue (both map to
        // the same buffer slot because the queue is full).
        /*
            这里也是一个 FastPath：如果我们去接收的时候，发现 buffer 是空的，但是
            发送等待队列不为空，那么直接从这个等待的 goroutine 中拷贝数据。
            如果 buffer 不为空，那么需要先从 buffer 中拿，然后将等待队列中的元素再放到 buffer 中
        */
        recv(c, sg, ep, func() { unlock(&c.lock) }, 3)
        return true, true
    }

    if c.qcount > 0 {
        // Receive directly from queue
        // 如果 buffer 中有数据可取，直接从 buffer 中拿
        qp := chanbuf(c, c.recvx)
        if raceenabled {
            racenotify(c, c.recvx, nil)
        }
        // 将 buffer 中的数据拷贝到目标地址
        if ep != nil {
            typedmemmove(c.elemtype, ep, qp)
        }
        // 清空 buffer 中取出的元素的内容
        typedmemclr(c.elemtype, qp)
        // 接收 index++
        c.recvx++
        if c.recvx == c.dataqsiz {
            c.recvx = 0
        }
        // buffer 中 总数--
        c.qcount--
        unlock(&c.lock)
        return true, true
    }

    // 如果非阻塞，返回 false
    if !block {
        unlock(&c.lock)
        return false, false
    }

    // no sender available: block on this channel.
    // 如果是阻塞的 channel，那么接收的 goroutine 将阻塞在这里
    // 将等待的 goroutine 打包成 sudog，并将其放到等待队列中，之后休眠
    gp := getg()
    mysg := acquireSudog()
    mysg.releasetime = 0
    if t0 != 0 {
        mysg.releasetime = -1
    }
    // No stack splits between assigning elem and enqueuing mysg
    // on gp.waiting where copystack can find it.
    mysg.elem = ep
    mysg.waitlink = nil
    gp.waiting = mysg
    mysg.g = gp
    mysg.isSelect = false
    mysg.c = c
    gp.param = nil
    c.recvq.enqueue(mysg)
    // Signal to anyone trying to shrink our stack that we're about
    // to park on a channel. The window between when this G's status
    // changes and when we set gp.activeStackChans is not safe for
    // stack shrinking.
    atomic.Store8(&gp.parkingOnChan, 1)
    gopark(chanparkcommit, unsafe.Pointer(&c.lock), waitReasonChanReceive, traceEvGoBlockRecv, 2)

    // 被唤醒
    // someone woke us up
    if mysg != gp.waiting {
        throw("G waiting list is corrupted")
    }
    gp.waiting = nil
    gp.activeStackChans = false
    if mysg.releasetime > 0 {
        blockevent(mysg.releasetime-t0, 2)
    }
    success := mysg.success
    gp.param = nil
    mysg.c = nil
    releaseSudog(mysg)
    // 如果 channel 没有被关闭，那就是真的 receive 到数据了
    return true, success
}
```

### 5. 关闭 channel

```go
func closechan(c *hchan) {
    // close 一个 nil channel 将 panic
    if c == nil {
        panic(plainError("close of nil channel"))
    }

    lock(&c.lock)
    // close 一个已经 closed 的 channel，将 panic
    if c.closed != 0 {
        unlock(&c.lock)
        panic(plainError("close of closed channel"))
    }

    if raceenabled {
        callerpc := getcallerpc()
        racewritepc(c.raceaddr(), callerpc, funcPC(closechan))
        racerelease(c.raceaddr())
    }

    // 明确关闭 channel
    c.closed = 1

    var glist gList

    // release all readers
    /*
        将所有的接收等待队列中的 goroutine 全部弹出，
        每一个 goroutine 将会收到 channel 中元素类型的零值，
        并且恢复到 Grunning 状态
    */
    for {
        sg := c.recvq.dequeue()
        if sg == nil {
            break
        }
        if sg.elem != nil {
            // 这一步设置零值
            typedmemclr(c.elemtype, sg.elem)
            sg.elem = nil
        }
        if sg.releasetime != 0 {
            sg.releasetime = cputicks()
        }
        gp := sg.g
        gp.param = unsafe.Pointer(sg)
        sg.success = false
        if raceenabled {
            raceacquireg(gp, c.raceaddr())
        }
        glist.push(gp)
    }

    // release all writers (they will panic)
    /*
        将所有发送队列中的 goroutine 全部弹出，并恢复到 Grunning 状态。
        恢复到后将继续进行“往 channel buffer 中发送数据”操作
        但这个方法中已经将 closed 设置成 1，恢复运行后会检查，如果已经 closed，则会直接 panic
    */
    for {
        sg := c.sendq.dequeue()
        if sg == nil {
            break
        }
        sg.elem = nil
        if sg.releasetime != 0 {
            sg.releasetime = cputicks()
        }
        gp := sg.g
        gp.param = unsafe.Pointer(sg)
        sg.success = false
        if raceenabled {
            raceacquireg(gp, c.raceaddr())
        }
        glist.push(gp)
    }
    unlock(&c.lock)

    // Ready all Gs now that we've dropped the channel lock.
    for !glist.empty() {
        gp := glist.pop()
        gp.schedlink = 0
        goready(gp, 3)
    }
}

```

## 二、使用

### 如何正确关闭 channel

不同的场景介绍几种建议方案，尤其是生产-消费模型相关的。

#### 1. M receivers, one sender, the sender says "no more sends" by closing the data channel

一个生产者、多个消费者，由 producer 来关闭 channel，通知数据已经发送完毕。

```go
func main(){
    consumerCnt := 10
    // 这里可以是缓冲的，也可以是非缓冲的
    taskChan := make(chan int, consumerCnt)
    wg := &sync.WaitGroup{}
    go func() {
        for i := 0; i < consumerCnt; i++ {
            wg.Add(1)
            go func(idx int) {
                defer wg.Done()
                for data := range taskChan {
                    fmt.Printf("consumer %d received: %d\n", idx, data)
                }
            }(i)
        }
    }()

    for i := 0; i < consumerCnt * 2; i++ {
        taskChan <- i
    }
    close(taskChan)

    wg.Wait()
}
```

#### 2. One receiver, N senders, the only receiver says "please stop sending more" by closing an additional signal channel

一个 consumer、多个 producer 场景，多添加一个用于 **通知** 的 channel，由其中一个消费者告诉生产者“已经够了，不要再发了”。

```go
func main(){
    rand.Seed(time.Now().UnixNano())
    producerCnt := 10
    taskChan := make(chan int)

    wg := &sync.WaitGroup{}

    // 用于信号通知
    stopChan := make(chan struct{})

    // 多个 producer 一直在生产消息，直到收到停止的信号
    for i := 0; i < producerCnt; i++ {
        go func(idx int) {
            for {
                // 这是一个 try-receive 操作，尝试能否快速退出
                select {
                case <-stopChan:
                    return
                default:
                }

                // 即使上面刚进行了判断没有退出，但到这一步的过程中 stopChan 可能就有数据 或者 被close了
                select {
                case <-stopChan:
                    return
                case taskChan <- rand.Intn(1000):
                }
            }
        }(i)
    }

    // 一个消费者
    wg.Add(1)
    go func() {
        defer wg.Done()
        for value := range taskChan {
            // 在这里确定要退出的逻辑
            if value%7 == 0 {
                fmt.Println(value)
                fmt.Printf("%d is times of 7, bye \n", value)
                // 在这里使用  close(stopChan) 和 stopChan <- struct{}{} 都能达到同样的效果
                close(stopChan)
                // stopChan <- struct{}{}
                return
            }
            fmt.Println(value)
        }
    }()

    wg.Wait()
}
```

#### 3. M receivers, N senders, any one of them says "let's end the game" by notifying a moderator to close an additional signal channel

多个 producer、多个 consumer 的场景下，当其中任何一个发生异常时，全部退出。这种场景下，不能让任何一个 producer 或者 consumer 来关闭 taskChan，也不能让任何一个 consumer 来关闭 stopChan 进而通知所有的 goroutine 退出。这个时候，我们可以再添加一个类似于主持人角色的 channel，让它来做 **close stopChan** 这个操作。

```go
func main(){
    rand.Seed(time.Now().UnixNano())

    const producerCnt = 10
    const consumerCnt = 100

    taskChan := make(chan int, consumerCnt)
    stopChan := make(chan struct{})

    // 这里必须使用有缓冲的 buffer，主要是为了避免 moderator 还没启动时就已经有一个 toStop 消息到达导致它没收到
    toStop := make(chan string, 1)

    var stoppedBy string
    // moderator
    go func() {
        stoppedBy = <-toStop
        close(stopChan)
    }()

    // producer
    for i := 0; i < producerCnt; i++ {
        go func(idx int) {
            for {
                value := rand.Intn(10000)
                if value == 0 {
                    // 达到退出的条件
                    /*
                        注意这里的用法，直接换成 toStop <- fmt.Sprintf("producer-%d", idx) 是否可行？
                        答案是不行，会造成死锁。
                    */
                    select {
                    case toStop <- fmt.Sprintf("producer-%d", idx):
                    default:
                    }
                    return
                }
                // 剩下的逻辑和前一个 demo 一样
                select {
                case <-stopChan:
                    return
                default:
                }

                select {
                case <-stopChan:
                    return
                case taskChan <- value:
                }
            }
        }(i)
    }

    wg := &sync.WaitGroup{}
    // consumer
    for i := 0; i < consumerCnt; i++ {
        wg.Add(1)
        go func(idx int) {
            defer wg.Done()
            for {
                select {
                case <-stopChan:
                    return
                default:
                }

                select {
                case <-stopChan:
                    return
                case value := <-taskChan:
                    // 达到 consumer 的退出条件
                    if value%7 == 0 {
                        select {
                        case toStop <- fmt.Sprintf("consumer-%d", value):
                        default:
                        }
                        return
                    }
                    fmt.Println(value)
                }
            }
        }(i)
    }
    wg.Wait()
    fmt.Println("exit by", stoppedBy)
}
```

注意当 producer 或者 consumer 达到退出的条件时，往 `toStop channel` 发送数据的方式。因为 `toStop` 的容量只有 1，直接使用 `toStop <- fmt.Sprintf("consumer-%d", value)` ，当 `toStop` 满了塞不下了，那么所有的往里面塞的 goroutine 都将被阻塞挂起，而这些 goroutine 还在等 `stopChan` 通知退出，而 `moderator` 的实现里，只接收一个，这就造成了死锁。所以正确做法是，通过 `select` 尝试往 `toStop` 中发送，成功还好，不成功(说明已经有其他的 goroutine 通知了)直接 `return`。
也可以不使用“通过 select 尝试发送”的方式，那就是让 `toStop` 的容量变成容纳所有可能发送的 goroutine 的数量，这个时候就可以放心直接往 `toStop` 里灌数据了：

```go
    // ...
    toStop := make(chan string, producerCnt + consumerCnt)
    // ...
    // producer 中达到退出条件
    toStop <- fmt.Sprintf("producer-%d", idx)

    // ...
    // consumer 中达到退出条件 
    toStop <- fmt.Sprintf("consumer-%d", idx)
```

#### 4. A variant of the "N sender" situation: the data channel must be closed to tell receivers that data sending is over

上面三个 demo 中，我们都没有对 `tashChan` 进行明确的 close，close 操作交给了 GC。但是有些场景下，会要求没数据时一定要关闭 `taskChan`，然后通知调用consumer明确告知“数据已经发送完了”。但是当有多个 producer 时，直接关闭肯定行不通。再这样的场景下，可以引入一个 `middle channel` ，producer 的数据不再直接发给 consumer，而是先发给`middle channel`，这个 `middle channel` 只有一个 sender，可以做到 `close taskChan` 了。

```go
    rand.Seed(time.Now().UnixNano())
    const producerCnt = 10
    const consumerCnt = 100

    taskChan := make(chan int)
    middleChan := make(chan int)
    closing := make(chan string)

    done := make(chan struct{})
    var stoppedBy string

    stop := func(by string) {
        select {
        case closing <- by:
            <-done
        case <-done:
        }
    }

    // 多个 producer，将数据发送给 middle channel
    for i := 0; i < producerCnt; i++ {
        go func(idx int) {
            for {
                select {
                case <-done:
                    return
                default:
                }

                value := rand.Intn(10000)
                if value%7 == 0 {
                    fmt.Println(value, " will stop")
                    stop("producer-" + strconv.Itoa(idx))
                    return
                }

                select {
                case <-done:
                    return
                case middleChan <- value:
                }
            }
        }(i)
    }

    // middle channel
    go func() {
        exit := func(v int, needSend bool) {
            close(done)
            if needSend {
                taskChan <- v
            }
            close(taskChan)
        }
        for {
            select {
            case stoppedBy = <-closing:
                exit(0, false)
                return
            case v := <-middleChan:
                select {
                case stoppedBy = <-closing:
                    exit(v, true)
                    return
                case taskChan <- v:
                }
            }
        }
    }()

    wg := &sync.WaitGroup{}
    // 多个 consumer
    for i := 0; i < consumerCnt; i++ {
        wg.Add(1)
        go func(idx int) {
            defer wg.Done()
            for {
                select {
                case <-done:
                    return
                default:
                }

                for value := range taskChan {
                    fmt.Println(value)
                }
            }
        }(i)
    }

    wg.Wait()
    fmt.Println("stopped by", stoppedBy)
```
