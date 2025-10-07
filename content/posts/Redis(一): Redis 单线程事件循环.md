---
title: "Redis系列(一): Redis 单线程事件循环"
author: JemmyHu(hujm20151021@gmail.com)
date: 2021-04-05T23:08:37+08:00
draft: false
mathjax: true
categories: ["技术博客", "redis","源码解析"]
tags: ["redis源码", "事件循环"]
comment: true
cover:
  image: https://pic.downk.cc/item/5f6b97cf160a154a67054cc8.jpg
summary:
---

## 一、前言

在关注 **redis 单线程/多线程** 时，有几个重要的时间节点：

1. Before `Redis v4.0`，真正的单线程；
2. `Redis v4.0`，引入多线程处理 `AOF` 等任务，但**核心的网络模型中依旧使用单线程**；
3. `Redis v6.0`，正式在网络模型中实现 `I/O多线程`。

从 `Redis v1.0` 到 `Redis v6.0以前`，Redis 的核心网络模型一直都是一个典型的 **单Reactor模型**，所有的事件都在这个线程内处理完成。本 issue 旨在解释清楚这个 **单Reactor模型** 的所有运作细节，为以后更好地理解新的 **Multi-Reactors/Master-Workers** 模型做准备。

**注：本文基于 `Redis v5.0.0` 版本分析**。

## 二、概览

`Reactor` 模式本质上指的是使用 `I/O多路复用(I/O multiplexing)` + `非阻塞 I/O(non-blocking I/O)` 的模式。传统的 `单Reactor` 模型中有三种角色：
![单 Reactor 模型](https://user-images.githubusercontent.com/38834787/124265326-1c21f000-db68-11eb-8240-91a697daf8d2.jpg)

- **Reactor**：主线程，模型核心，通过事件循环不断处理事件，如果是新的连接事件，则交给 `Acceptor`，如果是已经连接的 I/O 事件，则交给 `Handler`；
- **Acceptor**：负责 server 和 client 的连接。`Reactor` 模式一条最重要的原则就是：**I/O 操作不能阻塞主线程循环**，所以对于阻塞的网络 I/O，一般都是通过 `I/O 多路复用`实现的，如 Linux 上的`epoll`，这样可以最大程度地满足“一个线程非阻塞地监听多个 I/O 事件”。当有新的连接到来是，`Acceptor` 创建一个新的 `socket`，并将这个 `socket`添加到 `epoll` 的监听队列中，指定事件类型(读事件 或 写事件)，指定对应事件发生时的回调函数，这样当此客户端的请求到来时，`epoll` 会调用设定好的回调函数(可以理解成 Handler)；
- **Handler**：真正的业务处理逻辑。已经建立连接的客户端请求到来后，触发 `epoll` 的读事件，调用 `Handler` 执行具体的业务逻辑。

`Redis v6.0` 之前的网络模型就是一个典型的 `单Reactor` 模型：
![Redis Reactor 模型](https://user-images.githubusercontent.com/38834787/124294816-b561fe00-db8a-11eb-8562-7b26dfd4332d.jpg)
我们先逐一认识一下对应的角色概念：

- `aeEventLoop`：这是 `Redis` 自己实现的一个高性能事件库，里面封装了适配各个系统的 `I/O多路复用(I/O multiplexing)`，除了 socket 上面的事件以外，还要处理一些定时任务。服务启动时就一直循环，调用 `aeProcessEvent` 处理事件；
- `client` ：代表一个客户端连接。`Redis` 是典型的 `CS 架构（Client <---> Server）`，客户端通过 `socket` 与服务端建立网络通道然后发送请求命令，服务端执行请求的命令并回复。`Redis` 使用结构体 `client` 存储客户端的所有相关信息，包括但不限于封装的套接字连接 -- `*conn`，当前选择的数据库指针 --`*db`，读入缓冲区 -- `querybuf`，写出缓冲区 -- `buf`，写出数据链表 -- `reply`等；
- `acceptTcpHandler`：角色 `Acceptor` 的实现，当有新的客户端连接时会调用这个方法，它会调用系统 `accept` 创建一个 `socket` 对象，同时创建 `client` 对象，并将 socket 添加到 `EventLoop` 的监听列表中，并注册当对应的读事件发生时的回调函数 `readQueryFromClient`，即绑定 `Handler`，这样当该客户端发起请求时，就会调用对应的回调函数处理请求；
- `readQueryFromClient`：角色 `Handler` 的实现，主要负责解析并执行客户端的命令请求，并将结果写到对应的 `client->buf` 或者 `client->reply` 中；
- `beforeSleep`：事件循环之前的操作，主要执行一些常规任务，比如将 `client` 中的数据写会给客户端、进行一些持久化任务等。

有了这写概念，我们可以试着描绘一下 `客户端client` 与 `Redis server` 建立连接、发起请求到接收到返回的整个过程：

1. `Redis` 服务器启动，开启主线程事件循环 `aeMain`，注册 `acceptTcpHandler` 连接应答处理器到用户配置的监听端口对应的文件描述符，等待新连接到来；
2. 客户端和服务端建立网络连接，`acceptTcpHandler` 被调用，主线程将 readQueryFromClient 命令读取处理器绑定到新连接对应的文件描述符上作为对应事件发生时的回调函数，并初始化一个 `client` 绑定这个客户端连接；
3. 客户端发送请求命令，触发读就绪事件，主线程调用 `readQueryFromClient` 通过 `socket` 读取客户端发送过来的命令存入 `client->querybuf` 读入缓冲区；
4. 接着调用 `processInputBuffer`，在其中使用 `processInlineBuffer` 或者 `processMultibulkBuffer` 根据 `Redis` 协议解析命令，最后调用 `processCommand` 执行命令；
5. 根据请求命令的类型（`SET`, `GET`, `DEL`, `EXEC` 等），分配相应的命令执行器去执行，最后调用 `addReply` 函数族的一系列函数将响应数据写入到对应 `client` 的写出缓冲区：`client->buf` 或者 `client->reply` ，`client->buf` 是首选的写出缓冲区，固定大小 `16KB`，一般来说可以缓冲足够多的响应数据，但是如果客户端在时间窗口内需要响应的数据非常大，那么则会自动切换到 `client->reply`链表上去，使用链表理论上能够保存无限大的数据（受限于机器的物理内存），最后把 `client` 添加进一个 `LIFO` 队列 `clients_pending_write`；
6. 在事件循环 `aeMain` 中，主线程执行 `beforeSleep --> handleClientsWithPendingWrites`，遍历 `clients_pending_write` 队列，调用 `writeToClient` 把 `client` 的写出缓冲区里的数据回写到客户端，如果写出缓冲区还有数据遗留，则注册 `sendReplyToClient` 命令回复处理器到该连接的写就绪事件，等待客户端可写时在事件循环中再继续回写残余的响应数据。

## 三、事件库 aeEventLoop 实现细节

先来看核心数据结构：

```c
/* State of an event based program */
typedef struct aeEventLoop {
    int maxfd;   // 当前已经注册在此的最大文件描述符
    int setsize;  // 可“关心”的文件描述符数量
    long long timeEventNextId;  // 下一个 timer 的id
    time_t lastTime;     // 上一轮事件循环时的系统事件，用来诊断系统时间偏差
    aeFileEvent *events; // 注册的文件事件
    aeTimeEvent *timeEventHead; // 注册的时间事件
    aeFiredEvent *fired;  // 就绪的事件
    int stop;    // 事件轮询是否停止
    void *apidata; /* This is used for polling API specific data */
    aeBeforeSleepProc *beforesleep;  // 下一次事件轮训之前的钩子函数 
    aeBeforeSleepProc *aftersleep;   // 事件轮询结束后的钩子函数
} aeEventLoop;

/* File event structure */
typedef struct aeFileEvent {
    int mask; /* one of AE_(READABLE|WRITABLE) */
    aeFileProc *rfileProc;  // 读事件就绪时的回调函数 
    aeFileProc *wfileProc;  // 写事件就绪时的回调函数
    void *clientData;      // fd 对应的 client 实例
} aeFileEvent;

/* Time event structure */
typedef struct aeTimeEvent {
    long long id; /* time event identifier. */
    long when_sec; /* seconds */
    long when_ms; /* milliseconds */
    aeTimeProc *timeProc;
    aeEventFinalizerProc *finalizerProc;
    void *clientData;
    struct aeTimeEvent *next;
} aeTimeEvent;

/* A fired event */
typedef struct aeFiredEvent {
    int fd;
    int mask;
} aeFiredEvent;
```

> 关于 **时间事件** 和 **文件事件**，可参考：[redis 中的事件(时间事件和文件事件)到底是什么？](https://github.com/JemmyH/gogoredis/issues/2)

`aeEventLoop` 的 `Prototypes` 有很多，我们关注几个重要的：

### 1. `aeEventLoop *aeCreateEventLoop(int setsize)` 创建一个 `aeEventLoop` 实例

```c
aeEventLoop *aeCreateEventLoop(int setsize) {
    aeEventLoop *eventLoop;
    int i;

    if ((eventLoop = zmalloc(sizeof(*eventLoop))) == NULL) goto err;
    eventLoop->events = zmalloc(sizeof(aeFileEvent)*setsize);
    eventLoop->fired = zmalloc(sizeof(aeFiredEvent)*setsize);
    if (eventLoop->events == NULL || eventLoop->fired == NULL) goto err;
    eventLoop->setsize = setsize;
    eventLoop->lastTime = time(NULL);
    eventLoop->timeEventHead = NULL;
    eventLoop->timeEventNextId = 0;
    eventLoop->stop = 0;
    eventLoop->maxfd = -1;
    eventLoop->beforesleep = NULL;
    eventLoop->aftersleep = NULL;
    if (aeApiCreate(eventLoop) == -1) goto err;
    /* Events with mask == AE_NONE are not set. So let's initialize the
     * vector with it. */
    for (i = 0; i < setsize; i++)
        eventLoop->events[i].mask = AE_NONE;
    return eventLoop;

err:
    if (eventLoop) {
        zfree(eventLoop->events);
        zfree(eventLoop->fired);
        zfree(eventLoop);
    }
    return NULL;
}
```

这个方法的实现很简单，就是一些成员变量的初始化。需要注意的是 `aeApiCreate`，在 `src/ae.c` 的最开始，有下面的代码：

```c
/* Include the best multiplexing layer supported by this system.
 * The following should be ordered by performances, descending. */
#ifdef HAVE_EVPORT
#include "ae_evport.c"
#else
    #ifdef HAVE_EPOLL
    #include "ae_epoll.c"
    #else
        #ifdef HAVE_KQUEUE
        #include "ae_kqueue.c"
        #else
        #include "ae_select.c"
        #endif
    #endif
#endif
```

这段代码的意思是，根据当前的系统类型，选择性能最好的 `I/O多路复用` 库，比如当前系统是 Linux，那么应该使用 `ae_epoll`，Mac 下使用 `ae_kqueue`等，`ae_select` 是保底方案。而 `ae_xxx` 是对不同系统下的 `I/O多路复用` 的封装，将底层的不同系统调用都通过统一的 `API接口` 和 数据结构 `aeApiStates` 暴露出去，供上层调用。我们看下 Linux 系统中 `aeApiCreate` 的实现：

```c
typedef struct aeApiState {
    int epfd;
    struct epoll_event *events;
} aeApiState;

static int aeApiCreate(aeEventLoop *eventLoop) {
    aeApiState *state = zmalloc(sizeof(aeApiState));

    if (!state) return -1;
    state->events = zmalloc(sizeof(struct epoll_event)*eventLoop->setsize);
    if (!state->events) {
        zfree(state);
        return -1;
    }
    // 创建 epoll 实例
    state->epfd = epoll_create(1024); /* 1024 is just a hint for the kernel */
    if (state->epfd == -1) {
        zfree(state->events);
        zfree(state);
        return -1;
    }
    eventLoop->apidata = state;
    return 0;
}
```

而 Mac 下的实现又是这样的：

```c
typedef struct aeApiState {
    int kqfd;
    struct kevent *events;
} aeApiState;

static int aeApiCreate(aeEventLoop *eventLoop) {
    aeApiState *state = zmalloc(sizeof(aeApiState));

    if (!state) return -1;
    state->events = zmalloc(sizeof(struct kevent)*eventLoop->setsize);
    if (!state->events) {
        zfree(state);
        return -1;
    }
    state->kqfd = kqueue();
    if (state->kqfd == -1) {
        zfree(state->events);
        zfree(state);
        return -1;
    }
    eventLoop->apidata = state;
    return 0;
}
```

### 2. `aeCreateFileEvent(aeEventLoop *eventLoop, int fd, int mask, aeFileProc *proc, void *clientData)` 监听文件事件

```c
int aeCreateFileEvent(aeEventLoop *eventLoop, int fd, int mask, aeFileProc *proc, void *clientData)
{
    if (fd >= eventLoop->setsize) {
        errno = ERANGE;
        return AE_ERR;
    }
    aeFileEvent *fe = &eventLoop->events[fd];

    if (aeApiAddEvent(eventLoop, fd, mask) == -1)
        return AE_ERR;
    fe->mask |= mask;
    if (mask & AE_READABLE) fe->rfileProc = proc;
    if (mask & AE_WRITABLE) fe->wfileProc = proc;
    fe->clientData = clientData;
    if (fd > eventLoop->maxfd)
        eventLoop->maxfd = fd;
    return AE_OK;
}
```

同样，`aeApiAddEvent` 在不同系统下有不同的实现，在 Linux 系统中，会调用 `epoll_ctl` ，将 `fd` 添加到 `epoll` 实例的监听列表中，同时指定对应事件触发时的回调函数为 `*proc`。

### 3. `aeProcessEvents(aeEventLoop *eventLoop, int flags)` 事件轮训处理的核心逻辑

```c

/* The function returns the number of events processed. */
int aeProcessEvents(aeEventLoop *eventLoop, int flags)
{
    int processed = 0, numevents;

    // 只处理时间事件和文件事件
    if (!(flags & AE_TIME_EVENTS) && !(flags & AE_FILE_EVENTS)) return 0;

    // 先处理文件事件
    if (eventLoop->maxfd != -1 || ((flags & AE_TIME_EVENTS) && !(flags & AE_DONT_WAIT))) 
    {
     // 计算下一次时间事件到来之前应该阻塞等待的时长

        // 调用底层的 poll 函数，获取已经就绪的事件
        numevents = aeApiPoll(eventLoop, tvp);

        // 如果设置了 aftersleep 钩子函数，那应该在 poll 之后调用
        if (eventLoop->aftersleep != NULL && flags & AE_CALL_AFTER_SLEEP)
            eventLoop->aftersleep(eventLoop);

        // 调用对应事件的回调函数
        for (j = 0; j < numevents; j++) {
            aeFileEvent *fe = &eventLoop->events[eventLoop->fired[j].fd];
            int mask = eventLoop->fired[j].mask;
            int fd = eventLoop->fired[j].fd;
            int rfired = 0;

            // 读事件
            if (fe->mask & mask & AE_READABLE) {
                rfired = 1;
                fe->rfileProc(eventLoop,fd,fe->clientData,mask);
            }
            // 写事件
            if (fe->mask & mask & AE_WRITABLE) {
                if (!rfired || fe->wfileProc != fe->rfileProc)
                    fe->wfileProc(eventLoop,fd,fe->clientData,mask);
            }
            processed++;
        }
    }

    // 最后再处理时间事件
    if (flags & AE_TIME_EVENTS)
        processed += processTimeEvents(eventLoop);

    return processed; /* return the number of processed file/time events */
}
```

## 四、Redis 单线程流程详解

在这个 `section`，我们将通过源码的角度，看看 `section 1` 中的 Redis 的 `单Reactor` 网络模型中的实现细节，我们对照这张图开始：
![](https://user-images.githubusercontent.com/38834787/124294816-b561fe00-db8a-11eb-8562-7b26dfd4332d.jpg)

### 1. server 启动，创建 EventLoop

在 `src/server.c` 中的 `main` 方法中，当服务器启动时，会调用 `initServer`方法，在这个方法中，Redis 会创建全局唯一的 `aeEventLoop` 实例，并注册 `Server socket` 到对应的多路复用组件上，同时指定回调函数为 `acceptTcpHandler`，意思是服务器接收到新的连接时，应该调用 `acceptTcpHandler` 这个回调函数。

```c
void initServer(void)
{
    ...

    // 创建全局唯一的 EventLoop 实例
  server.el = aeCreateEventLoop(server.maxclients+CONFIG_FDSET_INCR);
    if (server.el == NULL) {
        serverLog(LL_WARNING,
            "Failed creating the event loop. Error message: '%s'",
            strerror(errno));
        exit(1);
    }   

    ...

    /* Create an event handler for accepting new connections in TCP and Unix
     * domain sockets. */
    // ipfd 表示服务启动是监听的 socket 对应的 fd，epoll 监听此 fd，有读事件发生(新连接到来)时调用回调函数 acceptTcpHandler
    for (j = 0; j < server.ipfd_count; j++) {
        if (aeCreateFileEvent(server.el, server.ipfd[j], AE_READABLE,
            acceptTcpHandler,NULL) == AE_ERR)
            {
                serverPanic(
                    "Unrecoverable error creating server.ipfd file event.");
            }
    }
}
    ....
```

### 2. 新连接到来时创建连接以及 client 实例

在前面我们将 server 对应的 socket 添加到 epoll 的监听队列，当有新的连接到来时，会触发读事件就绪，此时回调函数 `acceptTcpHandler` 就会被调用：

```c
void acceptTcpHandler(aeEventLoop *el, int fd, void *privdata, int mask) {
    ...
        // 创建 connect fd，代表 Redis Server 和客户端的一个连接(socket)
        cfd = anetTcpAccept(server.neterr, fd, cip, sizeof(cip), &cport);
        if (cfd == ANET_ERR) {
            if (errno != EWOULDBLOCK)
                serverLog(LL_WARNING,
                          "Accepting client connection: %s", server.neterr);
            return;
        }
        serverLog(LL_VERBOSE, "Accepted %s:%d", cip, cport);
        acceptCommonHandler(cfd, 0, cip);
}

static void acceptCommonHandler(int fd, int flags, char *ip) {
    client *c;
    // 1. 为 connect fd 创建一个 Client 对象
    if ((c = createClient(fd)) == NULL) {
        serverLog(LL_WARNING,
                  "Error registering fd event for the new client: %s (fd=%d)",
                  strerror(errno), fd);
        close(fd); /* May be already closed, just ignore errors */
        return;
    }
    // 2. 检查是否超过了最大连接数
    if (listLength(server.clients) > server.maxclients) {
        char *err = "-ERR max number of clients reached\r\n";

        /* That's a best effort error message, don't check write errors */
        if (write(c->fd, err, strlen(err)) == -1) {
            /* Nothing to do, Just to avoid the warning... */
        }
        server.stat_rejected_conn++;
        freeClient(c);
        return;
    }

    // 3. 检查 protect mode 是否开启，如果开启，不允许远程登录
    if (server.protected_mode && server.bindaddr_count == 0 && server.requirepass == NULL && !(flags & CLIENT_UNIX_SOCKET) && ip != NULL) {
        ...
    }

    server.stat_numconnections++;
    c->flags |= flags;
}

client *createClient(int fd) {
    client *c = zmalloc(sizeof(client));

    ...

    // 1. 标记 fd  为非阻塞
    anetNonBlock(NULL, fd);
    // 2. 设置不开启 Nagle 算法
    anetEnableTcpNoDelay(NULL, fd);
    // 3. 设置 KeepAlive
    if (server.tcpkeepalive)
        anetKeepAlive(NULL, fd, server.tcpkeepalive);
    // 4. 为 fd 创建对应的文件事件监听对应 socket 的读事件，并指定对应事件发生之后的回调函数为 readQueryFromClient
    if (aeCreateFileEvent(server.el, fd, AE_READABLE,
                          readQueryFromClient, c) == AE_ERR) {
        close(fd);
        zfree(c);
        return NULL;
    }

    // 5. 默认使用 0 号 db
    selectDb(c, 0);
    uint64_t client_id;
    // 6. 设置 client 其他默认属性
    atomicGetIncr(server.next_client_id, client_id, 1);
    c->id = client_id;
    c->fd = fd;
    ...
    return c;
}
```

在这个方法中，主要做了以下几件事：

1. 为新连接创建一个 socket，并将这个 socket 添加到 epoll 的监听队列中，注册读事件，并指定对应读事件触发后的回调函数为 `readQueryFromClient`；
2. 创建一个 `client` 对象，将 `client`、`socket` 等互相绑定，建立联系。

### 3. 客户端请求到来，执行具体的 handler

在 `createClient` 中我们知道对应客户端的 `socket` 上有事件发生时，回调函数是 `readQueryFromClient`。这个方法主要做一件事：将客户端的请求读取到 `client` 对象的 `querybuf` 中。之后再调用 `processInputBufferAndReplicate` 进一步处理请求。

```c
void readQueryFromClient(aeEventLoop *el, int fd, void *privdata, int mask) {
    ...

    // 调用 read 从 socket 中读取客户端请求数据到 client->querybuf
    c->querybuf = sdsMakeRoomFor(c->querybuf, readlen);
    nread = read(fd, c->querybuf+qblen, readlen);
    
    ...

    // 如果 client->querybuf 的大小超过 client_max_querybuf_len，直接返回错误，并关闭连接
    if (sdslen(c->querybuf) > server.client_max_querybuf_len) {
        sds ci = catClientInfoString(sdsempty(),c), bytes = sdsempty();

        bytes = sdscatrepr(bytes,c->querybuf,64);
        serverLog(LL_WARNING,"Closing client that reached max query buffer length: %s (qbuf initial bytes: %s)", ci, bytes);
        sdsfree(ci);
        sdsfree(bytes);
        freeClient(c);
        return;
    }

    // 处理客户端请求
    processInputBufferAndReplicate(c);
}
```

再来看 `processInputBufferAndReplicate` 的实现，它其实是 `processInputBuffer` 的封装，多加了一层判断：如果是普通的 server，则直接调用 `processInputBuffer` ；如果是主从客户端，还需要将命令同步到自己的从服务器中。

```c
void processInputBufferAndReplicate(client *c) {
    if (!(c->flags & CLIENT_MASTER)) {
        processInputBuffer(c);
    } else {
        size_t prev_offset = c->reploff;
        processInputBuffer(c);
        size_t applied = c->reploff - prev_offset;
        if (applied) {
            replicationFeedSlavesFromMasterStream(server.slaves,
                    c->pending_querybuf, applied);
            sdsrange(c->pending_querybuf,applied,-1);
        }
    }
}
```

`processInputBuffer` 会试着先从缓冲区中解析命令类型，判断类型，之后调用 `processCommand` 执行：

```c
void processInputBuffer(client *c) {
    // 设置 server 的当前处理 client 为c，可以理解为获得了 server 这把锁
    server.current_client = c;

    // 不断从 querybuf 中取出数据解析成成对的命令，直到 querybuf 为空
    while(c->qb_pos < sdslen(c->querybuf)) {
        // 进行一些 flags 的判断
        ...

        // 根据命令类型判断是 单条指令 还是 多条指令一起执行
        if (c->reqtype == PROTO_REQ_INLINE) {
            if (processInlineBuffer(c) != C_OK) break;
        } else if (c->reqtype == PROTO_REQ_MULTIBULK) {
            if (processMultibulkBuffer(c) != C_OK) break;
        } else {
            serverPanic("Unknown request type");
        }

        // 参数个数为 0 时重置客户端，可以接收下一个命令 
        if (c->argc == 0) {
            resetClient(c);
        } else {
            // 执行命令 
            if (processCommand(c) == C_OK) {
                // 集群信息同步
                if (c->flags & CLIENT_MASTER && !(c->flags & CLIENT_MULTI)) {
                    /* Update the applied replication offset of our master. */
                    c->reploff = c->read_reploff - sdslen(c->querybuf) + c->qb_pos;
                }

                // 如果不是阻塞状态，则重置client，可以接受下一个命令
                if (!(c->flags & CLIENT_BLOCKED) || c->btype != BLOCKED_MODULE)
                    resetClient(c);
            }
            // 释放“锁”
            if (server.current_client == NULL) break;
        }
    }

    // 重置 querybuf
    if (c->qb_pos) {
        sdsrange(c->querybuf,c->qb_pos,-1);
        c->qb_pos = 0;
    }

    server.current_client = NULL;
}
```

我们再来看 `processCommand`，在真正执行命令之前，会进行非常多的校验，校验通过后才会真正执行对应的命令。

```c
int processCommand(client *c) {
    // 1. 如果命令是 quit，则直接退出
    if (!strcasecmp(c->argv[0]->ptr, "quit")) {
        addReply(c, shared.ok);
        c->flags |= CLIENT_CLOSE_AFTER_REPLY;
        return C_ERR;
    }

    // 2. 在 command table 寻找对应命令的处理函数，
    c->cmd = c->lastcmd = lookupCommand(c->argv[0]->ptr);
    ...

    // 3. 用户权限校验
    if (server.requirepass && !c->authenticated && c->cmd->proc != authCommand) {
        flagTransaction(c);
        addReply(c, shared.noautherr);
        return C_OK;
    }

    // 4. 如果是集群模式，还需要处理集群 node 重定向
    if (server.cluster_enabled && !(c->flags & CLIENT_MASTER) && !(c->flags & CLIENT_LUA && server.lua_caller->flags & CLIENT_MASTER) &&
        !(c->cmd->getkeys_proc == NULL && c->cmd->firstkey == 0 && c->cmd->proc != execCommand)) {
        ...
    }

    // 5. 处理 maxmemory 情形
    if (server.maxmemory && !server.lua_timedout) {
        ...
    }

    // 6. 非 master 或者 磁盘有问题是，不要进行 AOF 等持久化操作
    int deny_write_type = writeCommandsDeniedByDiskError();
    if (deny_write_type != DISK_ERROR_TYPE_NONE &&
        server.masterhost == NULL &&
        (c->cmd->flags & CMD_WRITE ||
         c->cmd->proc == pingCommand)) {
        flagTransaction(c);
        if (deny_write_type == DISK_ERROR_TYPE_RDB)
            addReply(c, shared.bgsaveerr);
        else
            addReplySds(c,
                        sdscatprintf(sdsempty(),
                                     "-MISCONF Errors writing to the AOF file: %s\r\n",
                                     strerror(server.aof_last_write_errno)));
        return C_OK;
    }

    // 7. 当此服务器时master时：如果配置了 repl_min_slaves_to_write，当slave数目小于时，禁止执行写命令
    if (server.masterhost == NULL &&
        server.repl_min_slaves_to_write &&
        server.repl_min_slaves_max_lag &&
        c->cmd->flags & CMD_WRITE &&
        server.repl_good_slaves_count < server.repl_min_slaves_to_write) {
        flagTransaction(c);
        addReply(c, shared.noreplicaserr);
        return C_OK;
    }

    // 8. 当只读时，除了 master 的命令，不执行任何其他指令
    if (server.masterhost && server.repl_slave_ro &&
        !(c->flags & CLIENT_MASTER) &&
        c->cmd->flags & CMD_WRITE) {
        addReply(c, shared.roslaveerr);
        return C_OK;
    }

    // 9. 当客户端处于 Pub/Sub 时，只处理部分命令
    if (c->flags & CLIENT_PUBSUB &&
        c->cmd->proc != pingCommand &&
        c->cmd->proc != subscribeCommand &&
        c->cmd->proc != unsubscribeCommand &&
        c->cmd->proc != psubscribeCommand &&
        c->cmd->proc != punsubscribeCommand) {
        addReplyError(c, "only (P)SUBSCRIBE / (P)UNSUBSCRIBE / PING / QUIT allowed in this context");
        return C_OK;
    }

    // 10. 服务器为slave，但是没有连接 master 时，只会执行带有 CMD_STALE 标志的命令，如 info 等
    if (server.masterhost && server.repl_state != REPL_STATE_CONNECTED &&
        server.repl_serve_stale_data == 0 &&
        !(c->cmd->flags & CMD_STALE)) {
        flagTransaction(c);
        addReply(c, shared.masterdownerr);
        return C_OK;
    }

    // 11. 正在加载数据库时，只会执行带有 CMD_LOADING 标志的命令，其余都会被拒绝
    if (server.loading && !(c->cmd->flags & CMD_LOADING)) {
        addReply(c, shared.loadingerr);
        return C_OK;
    }

    // 12. 当服务器因为执行lua脚本阻塞时，只会执行部分命令，其余都会拒绝
    if (server.lua_timedout &&
        c->cmd->proc != authCommand &&
        c->cmd->proc != replconfCommand &&
        !(c->cmd->proc == shutdownCommand &&
          c->argc == 2 &&
          tolower(((char *) c->argv[1]->ptr)[0]) == 'n') &&
        !(c->cmd->proc == scriptCommand &&
          c->argc == 2 &&
          tolower(((char *) c->argv[1]->ptr)[0]) == 'k')) {
        flagTransaction(c);
        addReply(c, shared.slowscripterr);
        return C_OK;
    }

    // 13. 真正执行命令 
    if (c->flags & CLIENT_MULTI &&
        c->cmd->proc != execCommand && c->cmd->proc != discardCommand &&
        c->cmd->proc != multiCommand && c->cmd->proc != watchCommand) {
        // 如果是事务命令，则开启事务，命令进入等待队列
        queueMultiCommand(c);
        addReply(c, shared.queued);
    } else {
        // 否则调用 call 直接执行
        call(c, CMD_CALL_FULL);
        c->woff = server.master_repl_offset;
        if (listLength(server.ready_keys))
            handleClientsBlockedOnKeys();
    }
    return C_OK;
}
```

最后就是 `call` 函数，这是 Redis 执行命令的核心函数，它会处理通用的执行命令的前置和后续操作：

- 如果有监视器 `monitor`，则需要将命令发送给监视器；
- 调用 `redisCommand` 的 `proc` 方法，执行对应具体的命令逻辑；
- 如果开启了 `CMD_CALL_SLOWLOG`，则需要记录慢查询日志；
- 如果开启了 `CMD_CALL_STATS`，则需要记录一些统计信息；
- 如果开启了 `CMD_CALL_PROPAGATE`，则当 `dirty` 大于0时，需要调用 `propagate` 方法来进行命令传播(命令传播就是将命令写入 `repl-backlog-buffer` 缓冲中，并发送给各个从服务器中。)。

```c
void call(client *c, int flags)
{
    ....
    start = ustime();
    c->cmd->proc(c);
    duration = ustime() - start;
    ....
}
```

经过上面的过程，命令执行结束，对应的结果已经写在了 `client->buf`缓冲区 或者 `client->reply`链表中：`client->buf` 是首选的写出缓冲区，固定大小 `16KB`，一般来说可以缓冲足够多的响应数据，但是如果客户端在时间窗口内需要响应的数据非常大，那么则会自动切换到 `client->reply` 链表上去，使用链表理论上能够保存无限大的数据（受限于机器的物理内存），最后把 `client`添加进一个 `LIFO` 队列 `server.clients_pending_write`。

### 4. 在下一次事件循环之前，将写缓冲区中的数据发送给客户端

这个过程在主事件循环之前的钩子函数 `beforeSleep` 中，这个函数在 `main` 中指定，在 `aeMain` 中执行：

```c
int main(int argc, char **argv)
{
    ...
    aeSetBeforeSleepProc(server.el, beforeSleep);
    aeSetAfterSleepProc(server.el, afterSleep);
    aeMain(server.el);  // 启动单线程网络模型
    ....
}

void aeMain(aeEventLoop *eventLoop) {
    eventLoop->stop = 0;
    // 这是一个死循环，一直到 redis-server 停止
    while (!eventLoop->stop) {
        if (eventLoop->beforesleep != NULL)
            eventLoop->beforesleep(eventLoop);
        aeProcessEvents(eventLoop, AE_ALL_EVENTS|AE_CALL_AFTER_SLEEP);  // 处理三个事件：time file call_after_sleep
    }
}
```

再具体的实现中，我们只关注如何将写缓冲区的数据写回给客户端：

```c
void beforeSleep(struct aeEventLoop *eventLoop) {
    ...

    /* Handle writes with pending output buffers. */
    handleClientsWithPendingWrites();
    
    ....
}

int handleClientsWithPendingWrites(void) {
    listIter li;
    listNode *ln;
    int processed = listLength(server.clients_pending_write);

    // clients_pending_write 是一个 client 队列，listRewind 获取一个用于迭代的游标
    listRewind(server.clients_pending_write,&li);
    // 当队列不为空时，持续进行下面的逻辑处理
    while((ln = listNext(&li))) {
        client *c = listNodeValue(ln);
        c->flags &= ~CLIENT_PENDING_WRITE;
        // 将遍历过 client 从队列中删除 
        listDelNode(server.clients_pending_write,ln);

        /* If a client is protected, don't do anything,
         * that may trigger write error or recreate handler. */
        if (c->flags & CLIENT_PROTECTED) continue;

        // 将 client 的数据写回 client 对应的s ocket
        if (writeToClient(c->fd,c,0) == C_ERR) continue;

        // 这次一次性没发完，那就给对应 socket 创建额外的写事件
        if (clientHasPendingReplies(c)) {
            int ae_flags = AE_WRITABLE;
            /* For the fsync=always policy, we want that a given FD is never
             * served for reading and writing in the same event loop iteration,
             * so that in the middle of receiving the query, and serving it
             * to the client, we'll call beforeSleep() that will do the
             * actual fsync of AOF to disk. AE_BARRIER ensures that. */
            if (server.aof_state == AOF_ON &&
                server.aof_fsync == AOF_FSYNC_ALWAYS)
            {
                ae_flags |= AE_BARRIER;
            }
            if (aeCreateFileEvent(server.el, c->fd, ae_flags,
                sendReplyToClient, c) == AE_ERR)
            {
                    freeClientAsync(c);
            }
        }
    }
    return processed;
}
```

对 `client->buf` 和 `client->reply` 的处理在 `writeToClient` 方法中：

```c
/* Write data in output buffers to client. Return C_OK if the client
 * is still valid after the call, C_ERR if it was freed. */
int writeToClient(int fd, client *c, int handler_installed) {
    ssize_t nwritten = 0, totwritten = 0;
    size_t objlen;
    clientReplyBlock *o;

    while(clientHasPendingReplies(c)) {
        // 优先处理 buf，先发送一批。在执行之前会判断如果 client->buf 中有数据，则发送 client->buf 中的
        if (c->bufpos > 0) {
            nwritten = write(fd,c->buf+c->sentlen,c->bufpos-c->sentlen);
            if (nwritten <= 0) break;
            c->sentlen += nwritten;
            totwritten += nwritten;

            /* If the buffer was sent, set bufpos to zero to continue with
             * the remainder of the reply. */
            if ((int)c->sentlen == c->bufpos) {
                c->bufpos = 0;
                c->sentlen = 0;
            }
        } else {
            // client->buf 中没数据了，则处理 client->reply 链表中剩下的
            o = listNodeValue(listFirst(c->reply));
            objlen = o->used;

            if (objlen == 0) {
                c->reply_bytes -= o->size;
                listDelNode(c->reply,listFirst(c->reply));
                continue;
            }

            nwritten = write(fd, o->buf + c->sentlen, objlen - c->sentlen);
            if (nwritten <= 0) break;
            c->sentlen += nwritten;
            totwritten += nwritten;

            /* If we fully sent the object on head go to the next one */
            if (c->sentlen == objlen) {
                c->reply_bytes -= o->size;
                listDelNode(c->reply,listFirst(c->reply));
                c->sentlen = 0;
                /* If there are no longer objects in the list, we expect
                 * the count of reply bytes to be exactly zero. */
                if (listLength(c->reply) == 0)
                    serverAssert(c->reply_bytes == 0);
            }
        }
        if (totwritten > NET_MAX_WRITES_PER_EVENT &&
            (server.maxmemory == 0 ||
             zmalloc_used_memory() < server.maxmemory) &&
            !(c->flags & CLIENT_SLAVE)) break;
    }
    server.stat_net_output_bytes += totwritten;
    if (nwritten == -1) {
        if (errno == EAGAIN) {
            nwritten = 0;
        } else {
            serverLog(LL_VERBOSE,
                "Error writing to client: %s", strerror(errno));
            freeClient(c);
            return C_ERR;
        }
    }
    if (totwritten > 0) {
        /* For clients representing masters we don't count sending data
         * as an interaction, since we always send REPLCONF ACK commands
         * that take some time to just fill the socket output buffer.
         * We just rely on data / pings received for timeout detection. */
        if (!(c->flags & CLIENT_MASTER)) c->lastinteraction = server.unixtime;
    }
    // 数据全部发送完毕了，那么前一步因为没发完而创建的文件监听事件可以从 EventLoop 中删除了
    if (!clientHasPendingReplies(c)) {
        c->sentlen = 0;
        if (handler_installed) aeDeleteFileEvent(server.el,c->fd,AE_WRITABLE);

        /* Close connection after entire reply has been sent. */
        if (c->flags & CLIENT_CLOSE_AFTER_REPLY) {
            freeClient(c);
            return C_ERR;
        }
    }
    return C_OK;
}
```
