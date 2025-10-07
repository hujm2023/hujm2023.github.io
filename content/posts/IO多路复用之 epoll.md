---
title: "I/O多路复用之 epoll"
date: 2021-05-10T20:57:47+08:00
draft: false
author: JemmyHu(hujm20151021@gmail.com)
toc: true
mathjax: true
summary:
categories: [技术博客, 技术细节, Linux]
tags: [Linux, 多路复用, epoll]
comment: true
cover:
  image: https://pic.downk.cc/item/5f61dc63160a154a6777224d.png
---

## select 的缺陷

目前对于高并发的解决方案是 **一个线程处理所有连接**，在这一点上 `select` 和 `epoll` 是一样的。但 **当大量的并发连接存在、但短时间内只有少数活跃的连接时，`select` 的表现就显得捉襟见肘了。**

首先，`select` 用在有活跃连接时，所以，在高并发的场景下 `select` 会被非常频繁地调用。当监听的连接以数万计的时候，每次返回的只是其中几百个活跃的连接，这本身就是一种性能的损失。所以内核中直接限定死了 `select` 可监听的文件句柄数：

```c
// include/uapi/linux/posix_types.h
#define __FD_SETSIZE  1024
```

其次，内核中实现 `select` 的方式是 **轮询**，即每次检测都会遍历所有的 `fd_set` 中的句柄，时间复杂度为 `O(n)`，与 `fd_set` 的长度呈线性关系，`select` 要检测的句柄数越多就会越费时。

> `poll` 和 `select` 的实现机制没有太大差异，相比 `select`，`poll` 只是取消了最大监控文件描述符的限制，并没有从根本上解决 `select` 的缺陷。

下面这张图中所表达的信息中，当并发连接较小时，`select` 和 `epoll` 差距非常小，当并发数逐渐变大时，`select` 性能就显得非常乏力：
![主流IO多路复用机制benchmark](https://user-images.githubusercontent.com/38834787/121148015-fad52900-c873-11eb-8c03-bbe885baa2bd.jpeg)

需要注意的是，这个前提是 **保持大量连接，但是只有少数活跃连接**，如果活跃连接也特别多，那 `epoll` 也会有性能问题。

## epoll 相关的数据结构与方法

与 `epoll` 相关的系统调用有以下三个：
> 这三个方法可以在 Linux 系统的机器上通过 `man 2 xxx` 的方式查看具体用法

```c
/* 返回 epoll 实例的文件句柄，size 没有实际用途，传入一个大于 0 的数即可。 */
int epoll_create(int size);

/* 让 epoll(epfd)实例 对 目标文件(fd) 执行 `ADD | DEL | MOD` 操作，并指定”关心“的事件类型 */
int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event);

/* 阻塞等待所”关心“的事件发生 */
int epoll_wait(int epfd, struct epoll_event *events, int maxevents, int timeout);
```

与 `select` 相比，`epoll` 分清了 **频繁调用** 和 **不频繁调用** 的操作。例如，`epoll_ctl` 是不太频繁调用的，而 `epoll_wait` 是非常频繁调用的。

这是 `epoll` 最常见的 demo：

```c
#include <stdio.h>
#include <unistd.h>
#include <sys/epoll.h>

int main(void)
{
　　int epfd,nfds;
　　struct epoll_event ev; // ev用于注册事件，表示自己关心的事哪些事件
    struct epoll_event events[5]; // events 用于接收从内核返回的就绪事件
　　epfd = epoll_create(1); // 创建一个 epoll 实例
　　ev.data.fd = STDIN_FILENO; // 我们关心的是命令行输入
　　ev.events = EPOLLIN|EPOLLET; //监听读状态同时设置ET模式(这个后面会讲，可以简单理解成：文件内容发生变化时才会触发对应的事件)
　　epoll_ctl(epfd, EPOLL_CTL_ADD, STDIN_FILENO, &ev); // 注册epoll事件
　　for(;;)  
　　{
　　　　nfds = epoll_wait(epfd, events, 5, -1);  // 进入死循环，最后的 -1 表示无限期阻塞，直到有事件发生
       // epoll_wait 返回，表示有对应的事件发生，事件的信息存储在 events 数组中。nfds 表示数组的长度。接下来逐个处理事件
　　　　for(int i = 0; i < nfds; i++)
　　　　{
　　　　　　if(events[i].data.fd==STDIN_FILENO)
　　　　　　　　printf("welcome to epoll's word!\n");
　　　　}
　　}
}
```

接下来我们看看 `epoll` 相关的数据结构。

### eventpoll

```c
/*
 * This structure is stored inside the "private_data" member of the file
 * structure and represents the main data structure for the eventpoll
 * interface.
 */

struct eventpoll {
    // 保护 rbr(红黑树) 和 rdllist(等待队列) 
    struct mutex mtx;

    // 等待队列，用来保存对一个 epoll 实例调用 epoll_wait() 的所有进程。
    // 当调用 epoll_wait 的进程发现没有就绪的事件需要处理时，就将当前进程添加到此队列中，然后进程睡眠；后续事件发生，就唤醒这个队列中的所有进程(也就是出现了惊群效应)
    wait_queue_head_t wq;

    // 当被监视的文件是一个 epoll 类型时，需要用这个等待队列来处理递归唤醒。
    // epoll 也是一种文件类型，因此一个 epoll 类型的 fd 也是可以被其他 epoll 实例监视的。
    // 而 epoll 类型的 fd 只会有“读就绪”的事件。当 epoll 所监视的非 epoll 类型文件有“读就绪”事件时，当前 epoll 也会进入“读就绪”状态。
    // 因此如果一个 epoll 实例监视了另一个 epoll 就会出现递归。如 e2 监视了e1，e1 上有读就绪事件发生，e1 就会加入 e2 的 poll_wait 队列中。
    wait_queue_head_t poll_wait;

    // 就绪列表(双链表)，产生了用户注册的 fd读写事件的 epi 链表。
    struct list_head rdllist;

    // 保护 rdllist 和 ovflist 。
    rwlock_t lock;

    /* RB tree root used to store monitored fd structs */
    // 红黑树根结点，管理所有"关心"的 fd 
    struct rb_root_cached rbr;

    // 单链表，当 rdllist 被锁定遍历向用户空间发送数据时，rdllist 不允许被修改，新触发的就绪 epitem 被 ovflist 串联起来，
    // 等待 rdllist 被处理完了，重新将 ovflist 数据写入 rdllist
    struct epitem *ovflist;

    /* wakeup_source used when ep_scan_ready_list is running */
    struct wakeup_source *ws;

    /* The user that created the eventpoll descriptor */
    // 创建 eventpoll 的用户结构信息。
    struct user_struct *user;

    // eventpoll 对应的文件结构，Linux 中一切皆文件，epoll 也是一个文件。
    struct file *file;

    /* used to optimize loop detection check */
    u64 gen;
    struct hlist_head refs;
};
```

如上面 demo 中所示，

### epitem

```c
// 红黑树用于管理所有的要监视的文件描述符 fd。当我们向系统中添加一个 fd 时，就会对应地创建一个 epitem 结构体。
// epitem 可以添加到红黑树，也可以串联成就绪列表或其它列表。
struct epitem {
    union {
        /* RB tree node links this structure to the eventpoll RB tree */
        // 所在的红黑树
        struct rb_node rbn;
        /* Used to free the struct epitem */
        struct rcu_head rcu;
    };

    /* List header used to link this structure to the eventpoll ready list */
    // 所在的 eventpoll 的就绪列表
    struct list_head rdllink;

    /* Works together "struct eventpoll"->ovflist in keeping the single linked chain of items. */
    // 关联的 eventpoll 中的 ovflist
    struct epitem *next;

    /* The file descriptor information this item refers to */
    // 为最开始的 fd 创建 epitem 时的文件描述符信息
    struct epoll_filefd ffd;

    /* List containing poll wait queues */
    // poll 等待队列
    struct eppoll_entry *pwqlist;

    /* The "container" of this item */
    // 所在的 eventpoll 
    struct eventpoll *ep;

    /* List header used to link this item to the "struct file" items list */
    struct hlist_node fllink;

    /* wakeup_source used when EPOLLWAKEUP is set */
    struct wakeup_source __rcu *ws;

    /* The structure that describe the interested events and the source fd */
    struct epoll_event event;
};
```

## epoll 工作流程

`epoll` 是有状态的, 内核中维护了一个数据结构用来管理所要监视的 `fd`，这个数据结构是 `eventpoll`；  
在 `eventpoll` 中有一颗红黑树, 用来快速的查找和修改要监视的 `fd`，每个节点被封装成 `epitem` 结构；
在 `eventpoll` 中有一个列表, 用来收集已经发生事件的 `epitem` , 这个 `list` 叫 `ready list(rdllist)`。

通过 `epoll_ctl` 函数添加进来的事件都会被放在红黑树的某个节点内，所以，重复添加是没有用的。当把事件添加进来的时候会完成关键的一步——该事件都会与相应的设备（网卡）驱动程序建立回调关系，当相应的事件发生后，就会调用这个回调函数，该回调函数在内核中被称为：`ep_poll_callback`。这个回调函数其实就所把这个事件添加到rdllist这个双向链表中——一旦有事件发生，epoll就会将该事件添加到双向链表中。那么当我们调用 `epoll_wait` 时，`epoll_wait` 只需要检查 `rdlist` 双向链表中是否有存在注册的事件，有则返回，效率非常可观。

### `epoll_create` 细节

```c
// 创建一个 eventpoll 对象，并且关联文件资源
static int do_epoll_create(int flags)
{
    int error, fd;
    struct eventpoll *ep = NULL;
    struct file *file;

    // ...

    // 创建并初始化核心结构 eventpoll，赋值给 ep
    error = ep_alloc(&ep);
    if (error < 0)
        return error;

    // 创建一个文件(文件句柄 fd 和 file结构)
    fd = get_unused_fd_flags(O_RDWR | (flags & O_CLOEXEC));
    if (fd < 0) {
        error = fd;
        goto out_free_ep;
    }
    // 注意，在这里将 eventpoll 作为 file 的 private_data 保存起来，后面拿到 epoll 的文件描述符后，通过 file.private_data 就能拿到绑定的 eventpoll 对象
    file = anon_inode_getfile("[eventpoll]", &eventpoll_fops, ep,
                 O_RDWR | (flags & O_CLOEXEC));
    if (IS_ERR(file)) {
        error = PTR_ERR(file);
        goto out_free_fd;
    }
    // 绑定 fd 和 file，这个 fd 就是 epoll 实例的句柄，需要返回给用户进程。
    ep->file = file;
    fd_install(fd, file);
    return fd;
    // ...
}
```

这个函数很简单，主要做以下几件事：

1. 创建并初始化核心结构 `eventpoll`，赋值给变量 `ep`；
2. 创建一个 `文件句柄fd` 和 `文件 file结构体`，并绑定 `fd` 和 `file`、绑定 `file` 和 `eventpoll`(将 `eventpoll` 作为 `file` 的 `private_data` 保存起来，后面拿到 `epoll` 的文件描述符后，通过 `file.private_data` 就能拿到绑定的 `eventpoll` 对象)，这个 `fd` 就是 `epoll` 实例的句柄，需要返回给用户进程，这也间接说明 `epoll` 也是一种文件。

> 关于绑定 `fd` 和 `file`，参考：[彻底理解 Linux 中的 文件描述符(fd)](https://github.com/JemmyH/gogoredis/issues/6)

### `epoll_ctl` 细节

```c
// epoll_ctl 的详细实现
int do_epoll_ctl(
    int epfd/*epoll 文件描述符*/, 
    int op /*操作类型*/, 
    int fd /*要监控的目标文件描述符*/, 
    struct epoll_event *epds/*要监视的事件类型*/, 
    bool nonblock,
)
{
    int error;
    int full_check = 0;
    struct fd f, tf;
    struct eventpoll *ep;
    struct epitem *epi;
    struct eventpoll *tep = NULL;

    // epoll 对应的文件
    f = fdget(epfd);
    // fd 对应的文件
    tf = fdget(fd);

    /* The target file descriptor must support poll */
    // epoll 并不能监控所有的文件描述符，只能监视支持 poll 方法的文件描述符
    // 其实是检查对应的 file 中的 file_operations 中是否有 poll 方法，即当前文件类型是否实现了 poll 方法(普通文件没有实现，socket 或者 epoll 类型等都实现了，所以可以被 epoll 监控)
    if (!file_can_poll(tf.file))
        goto error_tgt_fput;

    /* Check if EPOLLWAKEUP is allowed */
    //  检查是否允许 EPOLLWAKEUP
    if (ep_op_has_event(op))
        ep_take_care_of_epollwakeup(epds);

    // epoll 监视的不是自己
    error = -EINVAL;
    if (f.file == tf.file || !is_file_epoll(f.file))
        goto error_tgt_fput;

    // 在 do_epoll_create 实现里 anon_inode_getfile 已经将 private_data 与 eventpoll 关联。
    ep = f.file->private_data;

    // 当我们添加进来的 file 是一个 epoll 类型的文件时，有可能造成循环引用的死循环。在这里提前检查避免这种情况 
    error = epoll_mutex_lock(&ep->mtx, 0, nonblock);
    if (error)
        goto error_tgt_fput;
    if (op == EPOLL_CTL_ADD) {
        if (READ_ONCE(f.file->f_ep) || ep->gen == loop_check_gen || is_file_epoll(tf.file)) {
            // ...
        }
    }

    // 查找 要添加的 fd 是否已经在红黑树上了，如果是，返回对应的 epitem 结构，否则返回 NULL
    epi = ep_find(ep, tf.file, fd);

    error = -EINVAL;
    switch (op) {
    case EPOLL_CTL_ADD:
        // 增加fd
        if (!epi) {
            epds->events |= EPOLLERR | EPOLLHUP;
            // fd 不在红黑树上，就将此 fd 添加到红黑树上管理。默认关注的事件是 EPOLLERR | EPOLLHUP
            error = ep_insert(ep, epds, tf.file, fd, full_check);
        } else
            error = -EEXIST;
        break;
    case EPOLL_CTL_DEL:
        // 删除fd
        if (epi)
            error = ep_remove(ep, epi);
        else
            error = -ENOENT;
        break;
    case EPOLL_CTL_MOD:
        // 修改fd事件类型
        if (epi) {
            if (!(epi->event.events & EPOLLEXCLUSIVE)) {
                epds->events |= EPOLLERR | EPOLLHUP;
                error = ep_modify(ep, epi, epds);
            }
        } else
            error = -ENOENT;
        break;
    }
    mutex_unlock(&ep->mtx);
    // ...
}
```

在 `do_epoll_ctl()` 的参数中，操作类型有三种：

- `EPOLL_CTL_ADD`： 往事件表中注册fd上的事件；
- `EPOLL_CTL_DEL`：删除fd上的注册事件；
- `EPOLL_CTL_MOD`：修改fd上的注册事件。

而 `struct epoll_event` 结构表示事件类型，常见的有：

```c
// eventpoll.h
#define EPOLLIN  (__force __poll_t)0x00000001 // 有可读数据到来
#define EPOLLPRI (__force __poll_t)0x00000002 // 有紧急数据可读：1. TCP socket 上有外带数据；2. 分布式环境下状态发生改变；3. cgroup.events类型的文件被修改
#define EPOLLOUT (__force __poll_t)0x00000004 // 有数据要写
#define EPOLLERR (__force __poll_t)0x00000008 // 文件描述符上发生错误(不管有没有设置这个 flag，epoll_wait 总是会检测并返回这样的错误)
#define EPOLLHUP (__force __poll_t)0x00000010 // 该文件描述符被挂断。常见 socket 被关闭（read == 0）
#define EPOLLRDHUP (__force __poll_t)0x00002000 // 对端已关闭链接，或者用 shutdown 关闭了写链

/* Set the Edge Triggered behaviour for the target file descriptor */
#define EPOLLET  ((__force __poll_t)(1U << 31))  // ET 工作模式

/* Set the One Shot behaviour for the target file descriptor */
/* 一般情况下，ET 模式只会触发一次，但有可能出现多个线程同时处理 epoll，此标志规定操作系统最多触发其上注册的一个可读或者可写或者异常事件，且只触发一次，如此无论线程再多，只能有一个线程或进程处理同一个描述符 */
#define EPOLLONESHOT ((__force __poll_t)(1U << 30)) 

/* Set exclusive wakeup mode for the target file descriptor */
/* 唯一唤醒事件，主要为了解决 epoll_wait 惊群问题。多线程下多个 epoll_wait 同时等待，只唤醒一个 epoll_wait 执行。 该事件只支持 epoll_ctl 添加操作 EPOLL_CTL_ADD */ 
#define EPOLLEXCLUSIVE ((__force __poll_t)(1U << 28))  
```

> 关于什么是 “ET(边缘触发)” 和 “LT(水平触发)”，后面会详细说。

#### ep_insert

```c
static int ep_insert(struct eventpoll *ep, const struct epoll_event *event, struct file *tfile, int fd, int full_check)
{
    // ep_insert(ep, epds, tf.file, fd, full_check);
    // tf 表示 fd 对应的 file 结构
    int error, pwake = 0;
    __poll_t revents;
    long user_watches;  // epoll 文件对象中所监视的 fd 数量
    struct epitem *epi;
    struct ep_pqueue epq;
    struct eventpoll *tep = NULL;  // 当 fd 类型是 epoll 时，tep 用来保存 fd 对应的 eventpoll 结构

    // 要监视的文件也是 epoll 类型，用 tep 保存对应的 eventepoll 结构
    if (is_file_epoll(tfile))
        tep = tfile->private_data;

    lockdep_assert_irqs_enabled();

    // 判断 epoll 监视的文件个数是否超出系统限制
    user_watches = atomic_long_read(&ep->user->epoll_watches);
    if (unlikely(user_watches >= max_user_watches))
        return -ENOSPC;
    if (!(epi = kmem_cache_zalloc(epi_cache, GFP_KERNEL)))
        return -ENOMEM;

    /* Item initialization follow here ... */
    // 创建一个双链表，头和尾都是它自己
    INIT_LIST_HEAD(&epi->rdllink);
    epi->ep = ep;
    ep_set_ffd(&epi->ffd, tfile, fd);  // epitem 与 fd 绑定
    epi->event = *event;
    epi->next = EP_UNACTIVE_PTR;

    // 目标文件是 epoll 类型
    if (tep)
        mutex_lock_nested(&tep->mtx, 1);
    /* Add the current item to the list of active epoll hook for this file */
    if (unlikely(attach_epitem(tfile, epi) < 0)) {
        kmem_cache_free(epi_cache, epi);
        if (tep)
            mutex_unlock(&tep->mtx);
        return -ENOMEM;
    }

    if (full_check && !tep)
        list_file(tfile);
    // 当前进程的用户的 epoll_watches 加一
    atomic_long_inc(&ep->user->epoll_watches);

    // 将初始化后的 epitem 添加到红黑树中
    ep_rbtree_insert(ep, epi);
    if (tep)
        mutex_unlock(&tep->mtx);

    // 不允许递归监视太多的 epoll 
    if (unlikely(full_check && reverse_path_check())) {
        ep_remove(ep, epi);
        return -EINVAL;
    }

    if (epi->event.events & EPOLLWAKEUP) {
        error = ep_create_wakeup_source(epi);
        if (error) {
            ep_remove(ep, epi);
            return error;
        }
    }

    /* Initialize the poll table using the queue callback */
    epq.epi = epi;
    // 注册回调函数，作用：add our wait queue to the target file wakeup lists. 在tcp_sock->sk_sleep中插入一个等待者
        // 不同的系统实现 poll 的方式不同，如socket的话, 那么这个接口就是 tcp_poll()
    init_poll_funcptr(&epq.pt, ep_ptable_queue_proc); 

    // 可能此时已经有事件存在了, revents返回这个事件
    revents = ep_item_poll(epi, &epq.pt, 1);

    // ...

    // 如果此时就有关注的事件发生，我们将其放到就绪队列中
    if (revents && !ep_is_linked(epi)) {
        list_add_tail(&epi->rdllink, &ep->rdllist);
        ep_pm_stay_awake(epi);

        // 唤醒等待的线程，告诉他们有活干了
        if (waitqueue_active(&ep->wq))
            wake_up(&ep->wq);
        if (waitqueue_active(&ep->poll_wait))
            pwake++;
    }
    // ...
}
```

`ep_insert` 先申请一个 `epitem` 对象 `epi`，并初始化 `epitem` 的两个 `list` 的头指针：`rdllink`(指向 `eventpoll` 的 `rdllist`)、`pwqlist`(指向包含此 `epitem` 的所有 `poll wait queue`)，通过 `fs` 将 `epitem`、`fd` 和 `file` 绑定，通过 `epitem.ep` 将此 `epitem` 和 传入的 `eventpoll` 对象绑定，通过传入的 `event` 对 `epitem.events` 赋值，紧接着，将这个 `epitem` 加入到 `eventpoll` 的 红黑树中。整个过程结束后，`epitem` 本身就完成了和 `eventpoll` 以及 `被监视文件fd` 的关联。但还要做一件事：将 `epitem` 加入目标文件的 `poll` 等待队列并注册对应的回调函数。

在 `ep_insert()` 中有一行是 `init_poll_funcptr(&epq.pt, ep_ptable_queue_proc);`，这其实是注册了一个回调函数——将文件的 `poll()` 方法与此方法绑定，当文件就绪，就会调用此方法。

> 关于 **等待队列** 的实现，参考：[理解 Linux 等待队列](https://github.com/JemmyH/gogoredis/issues/7)

我们知道，当一个进程加入等待队列之后，需要将设置对应的唤醒函数，当资源就绪的时候调用这个设置好的唤醒函数：

```c
// 链表中的一个结点
struct wait_queue_entry {
    unsigned int  flags; // 标志，如 WQ_FLAG_EXCLUSIVE，表示等待的进程应该独占资源（解决惊群现象）
    void   *private;  // 等待进程相关信息，如 task_struct
    wait_queue_func_t func; // 唤醒函数
    struct list_head entry; // 前后结点
};
```

我们再来看下 `init_waitqueue_func_entry` 这个方法：

```c
static inline void init_waitqueue_func_entry(struct wait_queue_entry *wq_entry, wait_queue_func_t func)
{
    wq_entry->flags  = 0;
    wq_entry->private = NULL;
    wq_entry->func  = func;
}
```

正是将等待队列中的结点的唤醒函数设置为 `ep_ptable_queue_proc` ！

我们来详细看看 `ep_ptable_queue_proc` 的实现：

```c
/*
// 当该文件描述符对应的文件有事件到达后，回调用这个函数
// 首先根据pt拿到对应的epi。然后通过pwq将三者关联。
// @file: 要监听的文件
// @whead: 该fd对应的设备等待队列，每个设备的驱动都会带
// @pt: 调用文件的poll传入的东西。
*/
static void ep_ptable_queue_proc(struct file *file, wait_queue_head_t *whead,
                 poll_table *pt)
{
    struct ep_pqueue *epq = container_of(pt, struct ep_pqueue, pt);
    struct epitem *epi = epq->epi;
    struct eppoll_entry *pwq;  // epitem 的私有项，为每一个 fd 保存内核的 poll。

    // 这个结构体主要完成 epitem 和 epitem事件发生时 callback 函数的关联，将唤醒回调函数设置为 ep_poll_callback，然后加入设备等待队列

    // ...

    // 将pwq的等待队列和回调函数ep_poll_callback关联
    // ep_poll_callback 才是真正意义上的 poll() 醒来时的回调函数，当设备就绪，就会唤醒设备的等待队列中的进程，此时 ep_poll_callback 会被调用
    init_waitqueue_func_entry(&pwq->wait, ep_poll_callback);
    pwq->whead = whead;
    pwq->base = epi;
    
    // 将 进程对应的等待双链表结点 放入等待队列whead
    // 将eppoll_entry挂在到fd的设备等待队列上。也就是注册epoll的回调函数 ep_poll_callback
    if (epi->event.events & EPOLLEXCLUSIVE)
        add_wait_queue_exclusive(whead, &pwq->wait);
    else
        add_wait_queue(whead, &pwq->wait);
    pwq->next = epi->pwqlist;
    epi->pwqlist = pwq;
}
```

我们来看看 `ep_poll_callback` 干了什么：

```c
/*
 * This is the callback that is passed to the wait queue wakeup
 * mechanism. It is called by the stored file descriptors when they
 * have events to report.
 *
 * This callback takes a read lock in order not to contend with concurrent
 * events from another file descriptor, thus all modifications to ->rdllist
 * or ->ovflist are lockless.  Read lock is paired with the write lock from
 * ep_scan_ready_list(), which stops all list modifications and guarantees
 * that lists state is seen correctly.
 */
static int ep_poll_callback(wait_queue_entry_t *wait, unsigned mode, int sync, void *key)
{
    int pwake = 0;
    struct epitem *epi = ep_item_from_wait(wait);
    struct eventpoll *ep = epi->ep;
    __poll_t pollflags = key_to_poll(key);
    unsigned long flags;
    int ewake = 0;

    // ...
    /*
     * If we are transferring events to userspace, we can hold no locks
     * (because we're accessing user memory, and because of linux f_op->poll()
     * semantics). All the events that happen during that period of time are
     * chained in ep->ovflist and requeued later on.
     */
    // 因为要访问用户空间，所以此时对 rdllist 的访问不应该加锁。如果恰巧这个时候有对应的
    // 事件发生，应该将其放到 ovflist 中之后再调度。
    if (READ_ONCE(ep->ovflist) != EP_UNACTIVE_PTR) {
        if (chain_epi_lockless(epi))
            ep_pm_stay_awake_rcu(epi);
    } else if (!ep_is_linked(epi)) {
        // 将当前的 epitem 添加到 eventpool 的就绪队列中 
        /* In the usual case, add event to ready list. */
        if (list_add_tail_lockless(&epi->rdllink, &ep->rdllist))
            ep_pm_stay_awake_rcu(epi);
    }

    /*
     * Wake up ( if active ) both the eventpoll wait list and the ->poll()
     * wait list.
     */
    // 同时唤醒 eventpool 和 poll 的等待的进程
    if (waitqueue_active(&ep->wq)) {
        if ((epi->event.events & EPOLLEXCLUSIVE) &&
                    !(pollflags & POLLFREE)) {
            switch (pollflags & EPOLLINOUT_BITS) {
            case EPOLLIN:
                if (epi->event.events & EPOLLIN)
                    ewake = 1;
                break;
            case EPOLLOUT:
                if (epi->event.events & EPOLLOUT)
                    ewake = 1;
                break;
            case 0:
                ewake = 1;
                break;
            }
        }
        wake_up(&ep->wq);
    }
    if (waitqueue_active(&ep->poll_wait))
        pwake++;
    
    // ...

    return ewake;
}
```

### `ep_wait` 细节

入口在

```c
SYSCALL_DEFINE4(epoll_wait, int, epfd, struct epoll_event __user *, events,
        int, maxevents, int, timeout)
{
    struct timespec64 to;

    return do_epoll_wait(epfd, events, maxevents,
                 ep_timeout_to_timespec(&to, timeout));
}
```

实际调用的是 `do_epoll_wait`：

```c
/*
 * Implement the event wait interface for the eventpoll file. It is the kernel
 * part of the user space epoll_wait(2).
 * 
 * @epfd: 对应的 eventpoll 文件描述符
 * @events:  用于接收已经就绪的事件
 * @maxevents：所监听的最大事件个数
 * @to：超时事件(-1表示无限制等待)
 */
// epoll_wait 的具体实现
static int do_epoll_wait(int epfd, struct epoll_event __user *events,
             int maxevents, struct timespec64 *to)
{
    int error;
    struct fd f;
    struct eventpoll *ep;

    /* The maximum number of event must be greater than zero */
    if (maxevents <= 0 || maxevents > EP_MAX_EVENTS)
        return -EINVAL;

    /* Verify that the area passed by the user is writeable */
    // 确保用户传进来的地址空间是可写的
    if (!access_ok(events, maxevents * sizeof(struct epoll_event)))
        return -EFAULT;

    /* Get the "struct file *" for the eventpoll file */
    // 获取 epoll 实例
    f = fdget(epfd);
    if (!f.file)
        return -EBADF;

    /*
     * We have to check that the file structure underneath the fd
     * the user passed to us _is_ an eventpoll file.
     */
    error = -EINVAL;
    // 确保传进来的 epfd 是 epoll 类型
    if (!is_file_epoll(f.file))
        goto error_fput;

    /*
     * At this point it is safe to assume that the "private_data" contains
     * our own data structure.
     */
    ep = f.file->private_data;

    /* Time to fish for events ... */
    // 执行具体的 poll，如果有事件产生，返回的 error 就是对应的事件个数，对应的事件也会同时从 eventpoll 对应的 rdllist(就绪队列) 中写入到传进来的 events 数组中
    error = ep_poll(ep, events, maxevents, to);

error_fput:
    fdput(f);
    return error;
}
```

我们看下 `ep_poll` 的实现细节：

```c
/**
 * ep_poll - 检索已经就绪的事件，并将其从内核空间传送到用户空间传进来的events 列表中
 *
 * @ep: eventpoll 实例指针
 * @events: 存放就绪事件的用户空间的数组的指针
 * @maxevents: events 数组的长度
 * @timeout: 获取就绪事件操作的最大超时时间。如果是 0，表示不阻塞；如果是负数，表示一直阻塞
 *
 * Return: 成功收到的事件的个数，或者失败时对应的错误码。
 */
static int ep_poll(struct eventpoll *ep, struct epoll_event __user *events,
           int maxevents, struct timespec64 *timeout)
{
    int res, eavail, timed_out = 0;
    u64 slack = 0;
    wait_queue_entry_t wait;
    ktime_t expires, *to = NULL;

    lockdep_assert_irqs_enabled();

    // 设置超时
    if (timeout && (timeout->tv_sec | timeout->tv_nsec)) {
        // 有具体的超时时长
        slack = select_estimate_accuracy(timeout);
        to = &expires;
        *to = timespec64_to_ktime(*timeout);
    } else if (timeout) {
        /*
         * Avoid the unnecessary trip to the wait queue loop, if the
         * caller specified a non blocking operation.
         */
        // 用户设置不阻塞。
        timed_out = 1;
    }

    // 检查 ep.rdllist 或 ep.ovflist 中是否有就绪的事件，如果有返回就绪事件的个数。否则返回 0
    eavail = ep_events_available(ep);

    while (1) {
        if (eavail) {
            // rdllist 中已经有事件了，将其传送到用户空间。
            // 如果没有对应的事件并且也没到超时时间，就再等等，直到超时
            res = ep_send_events(ep, events, maxevents);
            if (res)
                return res;
        }
        // 走到这一步，说明没有就绪事件
        // 用户设置不阻塞，直接返回
        if (timed_out)
            return 0;

        // always false
        eavail = ep_busy_loop(ep, timed_out);
        if (eavail)
            continue;

        // 检查当前进程是否有信号处理，返回不为0表示有信号需要处理。
        if (signal_pending(current))
            return -EINTR;

        init_wait(&wait);

        write_lock_irq(&ep->lock);

        __set_current_state(TASK_INTERRUPTIBLE);

        // 再次检查是否有就绪事件，如果没有，让当前进程睡眠(然后进程就阻塞在这里了...)
        eavail = ep_events_available(ep);
        if (!eavail)
            __add_wait_queue_exclusive(&ep->wq, &wait);

        write_unlock_irq(&ep->lock);

        // 重新计算超时时间
        if (!eavail)
            timed_out = !schedule_hrtimeout_range(to, slack,
                                  HRTIMER_MODE_ABS);

        // 进程被唤醒了，说明有事件发生！          
        __set_current_state(TASK_RUNNING);

        /*
         * We were woken up, thus go and try to harvest some events.
         * If timed out and still on the wait queue, recheck eavail
         * carefully under lock, below.
         */
        eavail = 1;

        if (!list_empty_careful(&wait.entry)) {
            write_lock_irq(&ep->lock);
            /*
             * If the thread timed out and is not on the wait queue,
             * it means that the thread was woken up after its
             * timeout expired before it could reacquire the lock.
             * Thus, when wait.entry is empty, it needs to harvest
             * events.
             */
            if (timed_out)
                // list_empty 检查 list 是否为空
                eavail = list_empty(&wait.entry);
            // 将 wait 从 ep 的等待队列中删除
            __remove_wait_queue(&ep->wq, &wait);
            write_unlock_irq(&ep->lock);
        }
    }
}
```

我们再来看 `ep_send_events`的实现：

```c
static int ep_send_events(struct eventpoll *ep,
              struct epoll_event __user *events, int maxevents)
{
    struct epitem *epi, *tmp;
    LIST_HEAD(txlist);
    poll_table pt;
    int res = 0;

    if (fatal_signal_pending(current))
        return -EINTR;

    init_poll_funcptr(&pt, NULL);

    mutex_lock(&ep->mtx);

    // 将 rdllist 中的元素全部添加到 txlist 中，并清空 ep.rdllist 
    ep_start_scan(ep, &txlist);

    // 迭代器，逐个处理从 ep->rdllist 中取出后放在 txlist 中的 epitem 
    // epi 表示正在处理的对象(cursor)
    list_for_each_entry_safe(epi, tmp, &txlist, rdllink) {
        struct wakeup_source *ws;
        __poll_t revents;

        if (res >= maxevents)
            break;

        ws = ep_wakeup_source(epi);
        if (ws) {
            if (ws->active)
                __pm_stay_awake(ep->ws);
            __pm_relax(ws);
        }

        // 重置 epitem 中的 rdllink
        list_del_init(&epi->rdllink);

        // 检查就绪事件的 flag 是否是调用方需要的
        revents = ep_item_poll(epi, &pt, 1);
        if (!revents)
            continue;

        // 内核向用户态复制数据
        if (__put_user(revents, &events->events) ||
            __put_user(epi->event.data, &events->data)) {
            list_add(&epi->rdllink, &txlist);
            ep_pm_stay_awake(epi);
            if (!res)
                res = -EFAULT;
            break;
        }
        res++;
        events++;
        // 处理水平触发和边缘触发的场景
        if (epi->event.events & EPOLLONESHOT)
            epi->event.events &= EP_PRIVATE_BITS;
        else if (!(epi->event.events & EPOLLET)) {
            list_add_tail(&epi->rdllink, &ep->rdllist);
            ep_pm_stay_awake(epi);
        }
    }
    ep_done_scan(ep, &txlist);
    mutex_unlock(&ep->mtx);

    return res;
}
```

而其中的 `ep_item_poll`，不同的驱动程序，都会有自己的 `poll` 方法，如果是 `TCP套接字`，这个`poll`方法就是 `tcp_poll`。在 `TCP` 中，会周期性的调用这个方法调用频率取决于协议栈中断频率的设置。一旦有事件到达后，对应的 `tcp_poll` 方法被调用，`tcp_poll` 方法会回调用 `sock_poll_wait()`，该方法会调用这里注册的 `ep_ptable_queue_proc` 方法。`epoll` 其实就是通过此机制实现将自己的回调函数加入到文件的 `waitqueue` 中的。这也是 `ep_ptable_queue_proc` 的目的。

```c
static __poll_t ep_item_poll(const struct epitem *epi, poll_table *pt,
                 int depth)
{
    struct file *file = epi->ffd.file;
    __poll_t res;

    pt->_key = epi->event.events;
    if (!is_file_epoll(file))
        // 非 epoll 类型的 fd，检查 socket 的就绪事件，fd 关联回调函数 ep_poll_callback。最终执行的 poll 是 tcp_poll
        res = vfs_poll(file, pt);
    else
        res = __ep_eventpoll_poll(file, pt, depth);
    return res & epi->event.events;
}
```

## 再谈 `epoll` 和 `select`

从更高的角度看，`epoll` 和 `select` 都是 `I/O 多路复用`，当我们在调用这类函数时，我们传入的是 **关心的socket**，接收到的返回是 **就绪的 socket**。那为何会有性能差距呢？我们尝试找出他们的不同点：

| 对比 |  select | epoll |
| :-:  | :-: | :-: |
|  连接数限制 |  1024 | 理论上无限制 |
| 内在处理机制 | 现行轮训 | callback |
| TODO| TODO| TODO |

再回头看看 `select` 的 demo:

```c
int main(){
    int fds[] = ...;  // 关心的 socket 数组
    fd_set source_fds; // 将我们关心的 socket 保存到 fd_set 中 
    fd_set temp_fds; // 临时变量，作为 select 的返回值

    // 初始化 source_fds
    FD_ZERO(&source_fds);
    for (int i=0; i<fds.length; i++) {
        FD_SET(fds[i], &source_fds);
    }

    while(1) {
        // select 将一个 fd_set 作为入参，将就绪的 socket 又填充如这个入参中作为出参返回
        // 因此，为了快速重置，设置一个临时变量，避免每次都要进行 source_fds 的重置
        temp_fds = source_fds;

        // select 会阻塞，直到关心的 socket 上有事件发生
        int n = select(..., &temp_fds, ...);
        // 在用户态遍历 socket，检查是否有我们关心的事件发生
        for (int i=0; i < fds.length; i++) {
            if (FD_ISSET(fds[i], &temp_fds)) {
                // ... 进行对应的逻辑处理
                FD_CLR(fds[i], &temp_fds);
            }
        }
    }

    return 0;
}
```

`select` 主要有两点限制：

1. 所能关注的 socket 太少，只能有 1024 个，对于一些大型 web 应用来说有点捉襟见肘；
2. 尽管 `FD_SET` 是 `O(1)` 的操作，但返回后还要在用户态遍历一次整个 `fd_set`，这是一个线性操作

再回过头来看 `epoll`:

```c
int main() {
    int fds[] = ...;  // 关心的 socket 数组
    int epfd = epoll_create(...); // 创建 epoll 实例
    // 将关心的 socket 添加到 epoll 中(红黑树等)
    for (int i=0; i < fds.length; i++){
        epoll_ctl(epfd,EPOLL_CTL_ADD, fds[i], ...);
    }

    // 定义一个结构，用来接收就绪的事件
    struct epoll_event events[MAX_EVENTS];
    while(1){
        // 如果无事件发生，那么进程将阻塞在这里
        // 如果有事件发生，则返回就绪的事件个数，同时事件被存储在 events 中
        int n = epoll_wait(epfd, &events,...);
        for (int i=0; i < n; i++) {
            // 通过下标取到返回的就绪事件，进行对应的逻辑处理
            new_event = events[i];
        }
    }

    return 0;
}
```

1. 每次`epoll_wait` 返回的都是活跃的 socket，根本不用全部遍历一遍
2. `epoll` 底层使用到了 **红黑树** 来存储所关心的 `socket`，查找效率有保证；注册的对应的事件通知是通过回调的方式执行的，这种解耦、相互协作的方式更有利于操作系统的调度。
