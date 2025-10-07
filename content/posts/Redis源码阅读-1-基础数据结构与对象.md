---
title: Redis源码阅读--1.基础数据结构与对象
author: JemmyHu(hujm20151021@gmail.com)
toc: true
mathjax: true
categories: [技术博客, 技术细节, Redis]
tags: [Redis, 基础数据结构]
comment: true
date: 2020-10-02 12:31:41
cover:
  image: https://pic.downk.cc/item/5f76adca160a154a674bc4da.png
summary:
---

首先明确，`Redis` 是一个**使用 C 语言编写的键值对存储系统**。`Redis` 是众所周知的 “**快**”，一方面，它是一个内存数据库，所有的操作都是在**内存**中完成的，内存的访问速度本身就很快；另一方面，得益于它**底层的数据结构**。`Redis` 的常见类型可在这个网页找到：[Redis 命令参考简体中文版](https://redis.readthedocs.io/en/2.4/index.html)，其使用到的底层数据结构有如下六种：**简单动态字符串**、**双向链表**、**压缩列表**、**哈希表**、**跳表**和 **整数数组**。本篇文章，将具体了解这些底层数据结构的实现。

> 本文所涉及源码位于：[https://github.com/redis/redis](https://github.com/redis/redis)，所选版本为 **6.0.8**。
>
> 绘图工具为 [draw.io](draw.io)
>
> 涉及到内存操作的函数：
>
> ```c
> void *zmalloc(size_t size); // 调用zmalloc函数，申请size大小的空间
> void *zcalloc(size_t size); // 调用系统函数calloc申请内存空间
> void *zrealloc(void *ptr, size_t size); // 原内存重新调整为size空间的大小
> void zfree(void *ptr);  // 调用zfree释放内存空间
> char *zstrdup(const char *s); // 字符串复制方法
> size_t zmalloc_used_memory(void); // 获取当前以及占用的内存空间大小
> void zmalloc_enable_thread_safeness(void); // 是否设置线程安全模式
> void zmalloc_set_oom_handler(void (*oom_handler)(size_t)); // 可自定义设置内存溢出的处理方法
> float zmalloc_get_fragmentation_ratio(size_t rss); // 获取所给内存和已使用内存的大小之比
> size_t zmalloc_get_rss(void); // 获取RSS信息(Resident Set Size)
> size_t zmalloc_get_private_dirty(void); // 获得实际内存大小
> size_t zmalloc_get_smap_bytes_by_field(char *field); // 获取/proc/self/smaps字段的字节数
> size_t zmalloc_get_memory_size(void); // 获取物理内存大小
> void zlibc_free(void *ptr); // 原始系统free释放方法
> ```

## 一、底层数据结构

### 1. 简单动态字符串

> 源码文件：[sds.h](https://github.com/redis/redis/blob/unstable/src/sds.h)

#### 1.1 数据结构

**SDS（Simple Dynamic Strings, 简单动态字符串）是 Redis 的一种基本数据结构，主要是用于存储字符串和整数。** 在 `Redis 3.2` 版本以前，`SDS` 的实现如下：

```c
struct sdshdr {
    // 记录 buf 数组中已使用字节的数量，等于 SDS 所保存字符串的长度
    int len;

    // 记录 buf 数组中未使用字节的数量
    int free;

    // 字节数组，用于保存字符串
    char buf[];
};
```

比如，字符串 `Redis6.0` 的结构如下：

![带有未使用空间的SDS](https://pic.downk.cc/item/5f768cb7160a154a67445538.png)

`SDS` 遵循 **`C` 字符串以空字符结尾**的惯例， 但保存空字符的 `1` 字节空间不计算在 SDS 的 `len` 属性里面， 并且为空字符分配额外的 `1` 字节空间， 以及添加空字符到字符串末尾等操作都是由 `SDS` 函数自动完成的， 所以这个空字符对于 `SDS` 的使用者来说是完全透明的——这样做的好处是，`SDS` 可以直接使用 `C` 库中的有关字符串的函数。

但是在 `Redis 3.2` 以后，为了提高效率以及更加节省内存，`Redis` 将 `SDS` 划分成一下五种类型：

- `sdshdr5`
- `sdshdr8`
- `sdshdr16`
- `sdshdr32`
- `sdshdr64`

先看 `sdshdr5`，增加了一个 `flags` 字段来标识类型，用一个字节(8 位)来存储：

```c
// Note: sdshdr5 is never used, we just access the flags byte directly.
struct __attribute__ ((__packed__)) sdshdr5 {
    unsigned char flags; /* 前 3 位表示类型, 后 5 为表示长度 */
    char buf[];
};
```

对于 `sdshdr5` ，因为其可存储长度最大为 `2^5 - 1 = 31`，当字符串长度超过 31 时，仅靠 `flag` 的后 5 为表示长度是不够的，这时需要使用其他的四个结构来保存：

```c
struct __attribute__ ((__packed__)) sdshdr8 {
    uint8_t len;                // 已使用长度 1字节
    uint8_t alloc;              // 总长度 1字节
    unsigned char flags;        // 前 3 位表示存储类型，后 5 位 预留
    char buf[];
};
struct __attribute__ ((__packed__)) sdshdr16 {
    uint16_t len;               // 已使用长度 2字节
    uint16_t alloc;             // 总长度 2字节
    unsigned char flags;        // 前 3 位表示存储类型，后 5 位 预留
    char buf[];
};
struct __attribute__ ((__packed__)) sdshdr32 {
    uint32_t len;               // 已使用长度 4字节
    uint32_t alloc;             // 总长度 4字节
    unsigned char flags;        // 前 3 位表示存储类型，后 5 位 预留
    char buf[];
};
struct __attribute__ ((__packed__)) sdshdr64 {
    uint64_t len;               // 已使用长度 8字节
    uint64_t alloc;             // 总长度 8字节
    unsigned char flags;        // 前 3 位表示存储类型，后 5 位 预留
    char buf[];
};
```

> C/C++ 中 `__packed` 的作用：
>
> 假设有以下结构体：
>
> ```c
> struct {
>    char a;      // 1 字节
>    int b;       // 4 字节
>    char c[2];   // 2 字节
>    double d;    // 8 字节
> }Struct_A;
> ```
>
> 在计算机内存中，**结构体变量的存储通常是按字长对齐的**，比如在 8 位机上，就按照 1 字节(8 位)对齐，上述结构体占用 `1+4+2+8=15​` 字节的内存；在 16 位机上，按照 2 字节对齐，则该结构体占用 `2+4+2+8=16​` 字节。也就是说，在更高位的机器中，如果按照默认的机器字长做内存对齐的标准，那总会有一些空间是浪费的，比如上面 16 位时，为了对齐，使用了 2 字节来存储一个`char`类型的变量。为什么要对齐？这是因为对内存操作按照整字存取会有更高的效率，是 “以空间换时间” 的思想体现。当然，在空间更优先的情况下，也可以不使用默认的机器字长做内存对齐，这个时候，使用 `__packed___`关键字，可以强制使编译器将结构体成员按照 1 字节进行内存对齐，可以得到非对齐的紧凑型结构体。

#### 1.2 API

- **创建 SDS**

```c
/* Create a new sds string starting from a null terminated C string. */
sds sdsnew(const char *init) {
    size_t initlen = (init == NULL) ? 0 : strlen(init);  // 拿到要创建的字符串的长度
    return sdsnewlen(init, initlen);  // 传入字符串、字符串长度，调用 sdsnewlen 动态分配内存
}
sds sdsnewlen(const void *init, size_t initlen) {
    void *sh;
    sds s;
    char type = sdsReqType(initlen);  // 根据字符串长度得到合适的类型
    // 一般情况下，创建一个空字符串的目的都是为了后面的append操作，因此，空字符串的情况下，直接创建SDS_TYPE_8，减少后面的扩容操作
    if (type == SDS_TYPE_5 && initlen == 0) type = SDS_TYPE_8;
    // 计算类型对应的结构体头部长度(len alloc flags的长度)
    int hdrlen = sdsHdrSize(type);
    // 指向flag的指针
    unsigned char *fp;

    // 申请内存，内存大小为 结构体头部长度+字符串长度(buf)+1，这里+1是因为要考虑 '\0' 字符
    sh = s_malloc(hdrlen+initlen+1);
    if (sh == NULL) return NULL;
    if (init==SDS_NOINIT)
        init = NULL;
    else if (!init)
        memset(sh, 0, hdrlen+initlen+1);
    // 将s指向buf
    s = (char*)sh+hdrlen;
    // 将 s-1 指向flag
    fp = ((unsigned char*)s)-1;
    // 对sds结构体变量进行赋值
    switch(type) {
        case SDS_TYPE_5: {
            *fp = type | (initlen << SDS_TYPE_BITS);
            break;
        }
        case SDS_TYPE_8: {
            SDS_HDR_VAR(8,s);
            sh->len = initlen;
            sh->alloc = initlen;
            *fp = type;
            break;
        }
        ...
    }
    if (initlen && init)
        memcpy(s, init, initlen);
    // 在s的最后添加'\0'
    s[initlen] = '\0';
    // 返回指向 buf 数组的指针s
    return s;
}
```

注意，创建 `SDS` 时返回给上层的是指向 `buf` 数组的指针 s，而不是结构体的指针，那如何找到结构体中的其他元素呢？上面提到了 `__packed__` 关键字，使用 1 字节进行内存对齐，那么知道了 `buf` 的地址，将其减去对应类型的长度(偏移量)，就能得到结构体中其他类型的地址。

- **清空 SDS**

清空一个 `SDS` 有两个途径：

第一种是直接调用 `s_free()` 函数：

```c
/* Free an sds string. No operation is performed if 's' is NULL. */
void sdsfree(sds s) {
    if (s == NULL) return;
    s_free((char*)s-sdsHdrSize(s[-1]));
}
```

另一种方式是 **重置 len 为 0** 的方式，这种情况下 `buf` 所占用的空间并没有被清除掉，新的数据会直接覆盖 `buf` 中的原有数据而无需再申请新的内存空间：

```c
/* Modify an sds string in-place to make it empty (zero length).
 * However all the existing buffer is not discarded but set as free space
 * so that next append operations will not require allocations up to the
 * number of bytes previously available. */
void sdsclear(sds s) {
    sdssetlen(s, 0);
    s[0] = '\0';
}
```

- **拼接 SDS**

拼接使用的是 `sds sdscatsds(sds s, sds t)`，但最终调用的还是 `sdscatlen`：

```c
// 将 t 拼接到 s 后面。调用此方法之后，sds底层的buf可能经过了扩容迁移了原来的位置，注意更新原来变量中对应的指针
sds sdscatsds(sds s, const sds t) {
    return sdscatlen(s, t, sdslen(t));
}
```

```c
sds sdscatlen(sds s, const void *t, size_t len) {
    size_t curlen = sdslen(s);  // 计算当前s的长度

    s = sdsMakeRoomFor(s,len);  // 空间不够的话扩容，确保s的剩余空间足够放得下t
    if (s == NULL) return NULL; // 扩容失败
    memcpy(s+curlen, t, len);   // 拼接
    sdssetlen(s, curlen+len);   // 更新s的属性len
    s[curlen+len] = '\0';       // 给s最后加上 '\0'
    return s;
}
```

接下来我们详细看一下扩容规则，在函数 `sdsMakeRoomFor` 中：

```c
// 将sds s的 buf 的可用空间扩大，使得调用此函数之后的s能够再多存储 addlen 长度的字符串。
// 注意：此方法并未改变 sds 的len属性，仅仅改变的是 sds 的 buf 数组的空间。
sds sdsMakeRoomFor(sds s, size_t addlen) {
    void *sh, *newsh;
    size_t avail = sdsavail(s);  // 当前的可用空间长度：s.alloc - s.len
    size_t len, newlen;
    char type, oldtype = s[-1] & SDS_TYPE_MASK;
    int hdrlen;

    // 情况1：剩余长度大于所需要长度，没必要扩容，直接返回
    if (avail >= addlen) return s;

    len = sdslen(s);     	// 当前字符串长度
    sh = (char*)s-sdsHdrSize(oldtype);
    newlen = (len+addlen);    // 新字符串长度

    // 情况2：扩容
    // 情况2.1： 如果 新长度 < 1MB，则按 新长度的2倍 扩容
    //    		否则，就按 新长度+1MB 扩容
    if (newlen < SDS_MAX_PREALLOC)
        newlen *= 2;
    else
        newlen += SDS_MAX_PREALLOC;

    // 计算新长度的类型
    type = sdsReqType(newlen);

    // 还是为了后续使用减少扩容次数的原因，将 sdshdr5 变为 sdshdr8
    if (type == SDS_TYPE_5) type = SDS_TYPE_8;

    hdrlen = sdsHdrSize(type);
    if (oldtype==type) {
        // 如果新长度对应的类型没变，则直接调用 s_realloc 扩大动态数组即可
        newsh = s_realloc(sh, hdrlen+newlen+1);
        if (newsh == NULL) return NULL;
        s = (char*)newsh+hdrlen;
    } else {
        /* Since the header size changes, need to move the string forward,
         * and can't use realloc */
        // 类型发生了改变，意味着sds结构体头部的三个属性的类型也要跟着变化，此时直接重新申请一块内存
        newsh = s_malloc(hdrlen+newlen+1);
        if (newsh == NULL) return NULL;
        // 原s的数据拷贝到新的内存上
        memcpy((char*)newsh+hdrlen, s, len+1);
        // 释放掉原来的s的空间，并将其更新为刚才新申请的
        s_free(sh);
        s = (char*)newsh+hdrlen;
        // 更新 flag
        s[-1] = type;
        // 更新 len
        sdssetlen(s, len);
    }
    // 更新 alloc
    sdssetalloc(s, newlen);
    return s;
}
```

代码中注释已经很清楚了，这里再总结一下扩容策略：如果 `剩余长度 avail` >= `新增长度 addlen` ，则无需扩容；否则，如果 `avail + addlen < 1MB`，按照 `2 * (avail + addlen)`扩容，否则按照 `avail + addlen + 1MB` 扩容。

#### 1.3 总结

- 创建 `SDS` 时返回的是指向 `buf` 数组的指针，而不是 `SDS` 类型的对象，这样的好处是兼容了已有的 C 语言中的相关函数；
- 读取内容时，先通过类对应类型计算偏移量，再通过 `len` 属性来限制读取的长度，杜绝了缓冲区溢出，二进制安全；
- 根据字符串的长度，定义了五种不同的类型，节省了空间；
- 进行字符串拼接时，会通过 `sdsMakeRoomFor` 函数来决定是否有底层 `buf` 数组的扩容操作。

### 2. 双端链表

> 源码文件：[adlist.h](https://github.com/redis/redis/blob/unstable/src/adlist.h)

#### 2.1 数据结构

当我们使用 `lpush` 或者 `rpush` 的时候，其实底层对应的数据结构就是一个双端链表。

首先我们来了解结点 `listNode`：

```c
typedef struct listNode {
    struct listNode *prev;  // 头指针
    struct listNode *next;  // 尾指针
    void *value;    		// 具体的值，因为值的类型不确定，此处使用万能指针
} listNode;
```

虽然使用多个 `listNode`就已经足够表示一个双端链表，但是为了更方便，`Redis` 还有如下结构：

```
typedef struct list {
    listNode *head;  // 头指针
    listNode *tail;  // 尾指针
    void *(*dup)(void *ptr);  // 拷贝结点函数
    void (*free)(void *ptr);  // 释放结点值函数
    int (*match)(void *ptr, void *key); // 判断两个结点是否相等的函数
    unsigned long len;  // 链表长度
} list;
```

他们的关系可用如下图表示：

![Redis双端链表](https://pic.downk.cc/item/5f769152160a154a6745655b.png)

#### 2.2 API

- **创建 `list` 对象**

创建的是一个 `list` 对象，首先会尝试申请分配空间，失败返回 `NULL` ：

```c
// 创建的只是一个 list 对象，这个对象可以被 AlFreeList() 释放掉，但是仅仅释放的是这个 list 对象，其上面的 listNode 对象还需要另外手动释放
list *listCreate(void)
{
    struct list *list;

    // 申请分配内存，失败返回 NULL
    if ((list = zmalloc(sizeof(*list))) == NULL)
        return NULL;
    // 给其他属性赋值
    list->head = list->tail = NULL;
    list->len = 0;
    list->dup = NULL;
    list->free = NULL;
    list->match = NULL;
    // 最终返回 list 对象
    return list;
}
```

- **添加元素 `listNode` 到 `list`**

给一个带头的双向链表添加元素，有三种添加方法：**头插入** 、 **尾插入** 和 指定位置，分别对应的操作为 `lpush` 、`rpush` 和 `linsert`。对于 `lpush` 和 `rpush` 的实现如下，本质上就是对双端链表的基础操作：

```c
list *listAddNodeHead(list *list, void *value)
{
    listNode *node;
	// 申请分配内存，失败返回 NULL
    if ((node = zmalloc(sizeof(*node))) == NULL)
        return NULL;
    node->value = value;

    // 将 listNode 插入到 list 的元素中
    if (list->len == 0) {
        // 如果之前 list 没有元素，那么 list 的 head 和 tail 均指向当前的 listNode
        list->head = list->tail = node;
        node->prev = node->next = NULL;
    } else {
        // 链表的头插入
        node->prev = NULL;
        node->next = list->head;
        list->head->prev = node;
        list->head = node;
    }
    // 更新 len
    list->len++;

    // 返回的是传进来的 list ，失败返回的是 NULL
    return list;
}

// 尾插入，过程和头插入类似
list *listAddNodeTail(list *list, void *value)
{
    listNode *node;

    if ((node = zmalloc(sizeof(*node))) == NULL)
        return NULL;
    node->value = value;
    if (list->len == 0) {
        list->head = list->tail = node;
        node->prev = node->next = NULL;
    } else {
        node->prev = list->tail;
        node->next = NULL;
        list->tail->next = node;
        list->tail = node;
    }
    list->len++;
    return list;
}

```

关于 `linsert` ，其用法如下：

> **`LINSERT key BEFORE|AFTER pivot value`**
>
> 将值`value`插入到列表`key`当中，位于值`pivot`之前或之后。
>
> 当`pivot`不存在于列表`key`时，不执行任何操作。
>
> 当`key`不存在时，`key`被视为空列表，不执行任何操作。
>
> 如果`key`不是列表类型，返回一个错误。

在 `Redis` 底层，对应的方法为 `listInsertNode`，当然，为了找到 `old_node`，前面还需要遍历 `list`，这个操作的时间复杂度是 `O(n)`，我们这里只关注如何插入元素：

```c
// 在 list 的 old_node 的前或后(after<0,在前面增加；after>0，在后面增加)新增值为 value 的新listNode
list *listInsertNode(list *list, listNode *old_node, void *value, int after) {
    listNode *node;

    // 为新增的 listNode 申请内存，失败返回 NULL
    if ((node = zmalloc(sizeof(*node))) == NULL)
        return NULL;
    node->value = value;

    if (after) {
        // after>0，在后面插入
        node->prev = old_node;
        node->next = old_node->next;
        if (list->tail == old_node) {
            list->tail = node;
        }
    } else {
        // after<0，在前面插入
        node->next = old_node;
        node->prev = old_node->prev;
        if (list->head == old_node) {
            list->head = node;
        }
    }
    if (node->prev != NULL) {
        node->prev->next = node;
    }
    if (node->next != NULL) {
        node->next->prev = node;
    }
    // 更新 len
    list->len++;
    // 成功 返回传进来的 list
    return list;
}
```

- **删除元素**

删除元素的情况有以下几种：清空整个 `list` ，删除某个 `listNode`。

我们先看清空整个 `list` ，它只是释放掉了这个 `list` 上连的所有的 `listNode` ，而 `list` 对象并没有被销毁：

```c
/* Remove all the elements from the list without destroying the list itself. */
void listEmpty(list *list)
{
    unsigned long len;
    listNode *current, *next;

    current = list->head;
    len = list->len;
    // 遍历整个链表，逐个释放空间，直到为空
    while(len--) {
        next = current->next;
        if (list->free) list->free(current->value);
        zfree(current);
        current = next;
    }
    list->head = list->tail = NULL;
    list->len = 0;
}
```

而下面这个 `listRelease` 方法，会释放所有：

```c
/* Free the whole list.
 *
 * This function can't fail. */
void listRelease(list *list)
{
    listEmpty(list);    // 先清空所有的 listNode
    zfree(list);		// 再释放 list
}
```

然后看删除某个具体的 `listNode`：

```c
void listDelNode(list *list, listNode *node)
{
    // 是否是 list 中的第一个元素
    if (node->prev)
        node->prev->next = node->next;
    else
        list->head = node->next;
    // 是否是 list 中的最后一个元素
    if (node->next)
        node->next->prev = node->prev;
    else
        list->tail = node->prev;
    // 释放当前节点的值
    if (list->free) list->free(node->value);
    // 释放内存
    zfree(node);
    // 更新 len
    list->len--;
}
```

#### 2.3 总结

- `Redis` 基于双端链表，可以提供各种功能：列表键、发布订阅功能、监视器等；
- 因为链表表头节点的前置节点和表尾节点的后置节点都指向 `NULL` ， 所以 `Redis` 的链表实现是无环链表；

- 仔细看过源代码后会发现，这是一个典型的双端链表，其底层实现与我在《数据结构》中遇到的如出一辙，这也从侧面说明了熟悉基本的数据结构的重要性。

### 3. 字典

字典，由一个个键值对构成，首先想一下，一个字典应该提供什么样的功能？键值对用来存储数据，之后还要能插入数据、修改数据、删除数据、遍历(读取)数据，字典最大的特点就是上面这些所有的操作都可以在 `O(1)` 的时间复杂度里完成。

比如在 `redis-cli` 中，我输入如下命令：

```bash
redis> set name Jemmy
```

这条命令在 `redis` 的内存中生成了一个键值对(`key-value`)，其中 `key` 是 `name`，`value` 是 `Jemmy`的字符串对象，

`Redis` 的字典采用 **哈希表** 来实现。一个哈希表，你可以简单把它想成一个数组，数组中的每个元素称为一个桶，这也就对应上我们经常所说，一个哈希表由多个桶组成，每个桶中保存了键值对的数据(**哈希桶中保存的值其实并不是值本身，而是一个指向实际值的指针**)。

提到哈希，首先要关注的是哈希算法以及解决哈希冲突的方式。哈希算法的具体实现我们暂时不关心，只需要知道 `Redis` 使用的是 [MurmurHash2](https://github.com/aappleby/smhasher)，“**这个算法的优点在于：即使输入的键是有规律的，算法仍能够给出一个很好的随机分布性，计算速度也很快**”；对于解决哈希冲突的方法，最常见的是 **开放地址法** 和 **拉链法**。二者实现原理在 **[Golang-map 详解](https://jemmyh.github.io/2020/09/18/golang-map-xiang-jie/)** 中已经说过，这里不再细讲，目前只需要知道，**`Redis` 采用拉链法解决哈希冲突**。

在 `Redis` 中，有以下几个概念：哈希表、哈希表结点和字典，他们的关系大致可以描述为：字典是一个全局的字典，一个字典中包含两个哈希表，一个正在使用，另一个用作扩容用；哈希表中包含多个哈希表结点。接下来我们详细看下每个结构的具体实现：

> 源码文件：[dict.h](https://github.com/redis/redis/blob/unstable/src/dict.h)

#### 3.1 数据结构

- **哈希表结点**

哈希表节点使用 `dictEntry` 结构表示， 每个 `dictEntry` 结构都保存着一个键值对：

```c
typedef struct dictEntry {
    // key
    void *key;

    // value，可以是指针 uint64_t int64_t double中的某一个
    union {
        void *val;
        uint64_t u64;
        int64_t s64;
        double d;
    } v;

    // 指向另一个哈希表结点的指针，连接哈希值相同的键值对，用来解决哈希冲突
    struct dictEntry *next;
} dictEntry;
```

- **哈希表**

```c
typedef struct dictht {
    dictEntry **table;          // dictEntry数组，dictEntry代表一个键值对
    unsigned long size;         // 哈希表大小(容量)
    unsigned long sizemask;     // 值总是等于 size - 1 ， 这个属性和哈希值一起决定一个键应该被放到 table 数组的哪个索引上面。
    unsigned long used;         // 哈希表已有结点的数量
} dictht;
```

下图可以表示 **哈希表 `dictht`** 和 **哈希表结点 `dictEntry`** 之间的关系：

![有一个键值对的哈希表](https://pic.downk.cc/item/5f7723fd160a154a67697c61.png)

- **字典**

```c
typedef struct dict {
    dictType *type;  // 类型对应的特定函数
    void *privdata;  // 私有数据
    dictht ht[2];    // 两个哈希表，一个正常使用，另一个用于扩容
    long rehashidx;  // rehash 索引值，扩容时使用，正常时为-1
    unsigned long iterators; // 正在运行的迭代器的数量
} dict;
```

这里的 `type` 是一个指向 `dictType` 结构体的指针，而每一个 `dictType` 结构体保存了 **一组用于操作特定类型键值对的函数**，不同的类型有不同的操作函数，`privdata` 保存了需要传递给特定类型函数的可选参数：

```c
typedef struct dictType {
    // 计算哈希值的函数
    uint64_t (*hashFunction)(const void *key);
    // 复制键的函数
    void *(*keyDup)(void *privdata, const void *key);
    // 复制值的函数
    void *(*valDup)(void *privdata, const void *obj);
    // 对比键是否相同的函数
    int (*keyCompare)(void *privdata, const void *key1, const void *key2);
    // 销毁键的函数
    void (*keyDestructor)(void *privdata, void *key);
    // 销毁值的函数
    void (*valDestructor)(void *privdata, void *obj);
} dictType;
```

`ht` 属性是一个包含两个项的数组， 数组中的每个项都是一个 `dictht` 哈希表， 一般情况下， 字典只使用 `ht[0]` 哈希表， `ht[1]` 哈希表只会在对 `ht[0]` 哈希表进行 rehash 时使用。

除了 `ht[1]` 之外， 另一个和 rehash 有关的属性就是 `rehashidx` ： 它记录了 rehash 目前的进度， 如果目前没有在进行 rehash ， 那么它的值为 `-1` 。

下图展示了一个普通状态(没有进行 `rehash` )的字典：

![未扩容的字典示例](https://pic.downk.cc/item/5f772abc160a154a676b8909.png)

#### 3.2 哈希冲突的解决方式

当两个以上的键经过哈希函数计算之后，落在了哈希表数组的同一个索引上面，我们就称这些键发生了 **哈希冲突(hash collision)**。

Redis 的哈希表使用 **链接法**来解决键冲突： 每个哈希表节点(`dictEntry`)都有一个 `next` 指针， 多个哈希表节点可以用 `next` 指针构成一个单向链表， 被分配到同一个索引上的多个节点可以用这个单向链表连接起来， 这就解决了键冲突的问题。写入时，因为没有直接指向链的最后一个元素的指针，因此为了更少的时间复杂度， `Redis` 采用的是在链表头部插入；读取时，先定位到链头，之后逐个比较值是否与所求相同，直到遍历完整个链。

比如上图中，在 `dictht.table` 的 3 号桶中已经存在一个键值对 `k1-v1`，此时又新加入一个键值对 `k2-v2`，经过哈希计算后正好也落在 3 号桶中，经过插入后结果如下：

![哈希冲突示例](https://pic.downk.cc/item/5f773530160a154a676eef06.png)

#### 3.4 rehash 细节

当哈希表的键值对数量太多或者太少时，需要根据实际情况对哈希表的大小进行扩大或者缩小，这个过程通过 `rehash(重新散列)` 来完成。 而判断是否进行 `rehash` ，是在向哈希表插入一个键值对的时候，接下来我们通过分析源代码的方式，详细了解 `rehash` 的细节。

首先，添加一个新键值对，用到的是 `dictAdd` 方法：

```c
/* Add an element to the target hash table */
int dictAdd(dict *d, void *key, void *val)
{
    dictEntry *entry = dictAddRaw(d,key,NULL);  // 将键值对封装成dictEntry

    if (!entry) return DICT_ERR;                // 如果创建dictEntry，返回失败
    dictSetVal(d, entry, val);                  // 键不存在，则设置dictEntry结点的值
    return DICT_OK;
}
```

我们接着看 `dictAddRaw`，这一步主要将键值对封装成一个 `dictEntry` 并返回 ：

```c
// 将 key 插入哈希表中
dictEntry *dictAddRaw(dict *d, void *key, dictEntry **existing)
{
    long index;
    dictEntry *entry;
    dictht *ht;

    // 如果哈希表正在rehash，则向前 rehash一步(渐进式rehash的体现)
    // 是否正在进行 rehash，是通过 dict.rehashidx == -1 来判断的
    if (dictIsRehashing(d)) _dictRehashStep(d);

    // 调用_dictKeyIndex() 检查键是否存在，如果存在则返回NULL
    if ((index = _dictKeyIndex(d, key, dictHashKey(d,key), existing)) == -1)
        return NULL;

    // 获取当前正在使用的ht，如果正在 rehash，使用 ht[1]，否则使用 ht[0]
    ht = dictIsRehashing(d) ? &d->ht[1] : &d->ht[0];
    // 为新增的节点分配内存
    entry = zmalloc(sizeof(*entry));
    // 将结点插入链表头部
    entry->next = ht->table[index];
    ht->table[index] = entry;
    // 更新结点数量
    ht->used++;

    // 设置新节点的键，使用的是 type 属性中的 keyDup 函数
    dictSetKey(d, entry, key);
    return entry;
}
```

我们再看 `_dictKeyIndex` 这个方法，作用是计算某个 `key` 应该存储在哪个空的 `bucket` ，即需要返回这个 `key` 应该存储在 `dictEntry` 数组的 `index`，如果已经存在，返回 -1。需要注意的是，当哈希表正在 `rehash` 时，返回的 `index` 应该是要搬迁的 `ht`：

```c
// 传进来的 existing 是 NULL, hash是通过 type 中的哈希函数计算的
static long _dictKeyIndex(dict *d, const void *key, uint64_t hash, dictEntry **existing)
{
    unsigned long idx, table;
    dictEntry *he;
    if (existing)
        *existing = NULL;

    // 检查是否需要扩展哈希表，如果需要则进行扩展
    if (_dictExpandIfNeeded(d) == DICT_ERR)
        return -1;

    for (table = 0; table <= 1; table++)
    {
        idx = hash & d->ht[table].sizemask;
        /* Search if this slot does not already contain the given key */
        he = d->ht[table].table[idx];
        while (he)
        {
            if (key == he->key || dictCompareKeys(d, key, he->key))
            {
                if (existing)
                    *existing = he;
                return -1;
            }
            he = he->next;
        }
        if (!dictIsRehashing(d))
            break;
    }
    return idx;
}
```

最后，我们关注 **检查是否需要 `rehash`，需要则启动** 的 `_dictExpandIfNeeded`：

```c
static int _dictExpandIfNeeded(dict *d)
{
    // 如果正在 rehash，直接返回
    if (dictIsRehashing(d))
        return DICT_OK;

    /* If the hash table is empty expand it to the initial size. */
    // 如果哈希表中是空的，则将其收缩为初始化大小 DICT_HT_INITIAL_SIZE=4
    if (d->ht[0].size == 0)
        return dictExpand(d, DICT_HT_INITIAL_SIZE);

    // 在 (ht[0].used/ht[0].size)>=1前提下，如果 系统允许扩容 或者 ht[0].used/t[0].size>5 时，容量扩展为原来的2倍
    if (d->ht[0].used >= d->ht[0].size &&
        (dict_can_resize ||
         d->ht[0].used / d->ht[0].size > dict_force_resize_ratio))
    {
        return dictExpand(d, d->ht[0].used * 2);  // 扩容至原来容量的2倍
    }
    return DICT_OK;
}
```

仔细看看 `dictExpand` 是如何扩展哈希表容量的，这个函数中，判断是否需要扩容，如果需要，则新申请一个 `dictht` ，赋值给 `ht[0]`，然后将字典的状态设置为 **正在 `rehash`(rehashidx > -1)**，需要注意的是，这个方法中并没有实际进行键值对的搬迁：

```c
// 扩容 或者 新建一个 dictht
int dictExpand(dict *d, unsigned long size)
{
    /* the size is invalid if it is smaller than the number of
     * elements already inside the hash table */
    // 如果正在 reahsh 或者 传进来的size不合适(size比当前已有的容量小，正常情况下这是不可能的)，直接返回错误
    if (dictIsRehashing(d) || d->ht[0].used > size)
        return DICT_ERR;

    dictht n; // 新哈希表
    // 计算 扩展或缩放新哈希表容量 的大小，必须是2的倍数
    unsigned long realsize = _dictNextPower(size);

    // 如果计算扩容后的新哈希表的容量，和原来的相同，就没必要扩容，直接返回错误
    if (realsize == d->ht[0].size)
        return DICT_ERR;

    // 为新哈希表申请内存，并将所有的指针初始化为NULL
    n.size = realsize;
    n.sizemask = realsize - 1;
    n.table = zcalloc(realsize * sizeof(dictEntry *));
    n.used = 0;

    /* Is this the first initialization? If so it's not really a rehashing
     * we just set the first hash table so that it can accept keys. */
    // 如果原来的哈希表是空的，意味着这是在新建一个哈希表，将新申请的 dictht 赋值给 ht[0]，直接返回创建成功
    if (d->ht[0].table == NULL)
    {
        d->ht[0] = n;
        return DICT_OK;
    }

    // 如果不是新建哈希表，那就是需要实打实的扩容，此时将刚才新申请的 哈希表 赋值给 ht[1]，并将当前字典状态设置为"正在rehash"(rehashidx > -1)
    d->ht[1] = n;
    d->rehashidx = 0;
    return DICT_OK;
}

// 哈希表的容量必须是 2的倍数
static unsigned long _dictNextPower(unsigned long size)
{
    unsigned long i = DICT_HT_INITIAL_SIZE;

    if (size >= LONG_MAX)
        return LONG_MAX + 1LU;
    while (1)
    {
        if (i >= size)
            return i;
        i *= 2;
    }
}
```

什么时候进行 **桶** 的搬迁呢？这里涉及到一个名词：**渐进式扩容**。我们知道，扩展或收缩哈希表需要将 `ht[0]` 里面的所有键值对 `rehash` 到 `ht[1]` 里面，如果哈希表中的键值对数量少，那么一次性转移过去不是问题；但是键值对的数量很大，几百万几千万甚至上亿，那么一次性搬完的计算量+单线程很有可能使 `redis` 服务停止一段时间。因此，为了避免 `rehash` 对服务造成影响，服务不是一次性 `rehash` 完成的，而是 **分多次**、**渐进式**地将 `ht[0]` 中的键值对搬迁到 `ht[1]` 中。

源码中真正执行搬迁的函数是 `_dictRehashStep`：

```c
// _dictRehashStep 让 rehash 的动作向前走一步(搬迁一个桶)，前提是当前字典没有被遍历，即iterators==0，iterators表示当前正在遍历此字典的迭代器数目
static void _dictRehashStep(dict *d)
{
    if (d->iterators == 0)
        dictRehash(d, 1);
}
```

再看 `dictRehash` ：

```c
// dictRehash 向前 rehash n步。如果还没有搬迁完，返回 1，搬迁完成返回0
int dictRehash(dict *d, int n)
{
    // 当dictRehash时，rehashidx指向当前正在被搬迁的bucket，如果这个bucket中一个可搬迁的dictEntry都没有，说明就没有可搬迁的数据。
    // 这个时候会继续向后遍历 ht[0].table 数组，直到找到下一个存有数据的bucket位置，如果一直找不到，则最多向前走 empty_visits 步，本次搬迁任务结束。
    int empty_visits = n * 10;
    // 整个dict的 rehash 完成了，返回0
    if (!dictIsRehashing(d))
        return 0;

    // 外层大循环，确保本次最多向前走n步 以及 ht[0].table中还有值
    while (n-- && d->ht[0].used != 0)
    {
        dictEntry *de, *nextde;

        // 确保 rehashidx 不会超过 ht[0].table 的长度，因为 rehashidx 指向当前正在被搬迁的bucket，其实就是 ht[0].table 数组的下标，这里保证数组下标访问不会越界
        assert(d->ht[0].size > (unsigned long)d->rehashidx);

        // 当前的bucket搬迁完了，继续寻找下一个bucket，知道全部为空 或者 向前走的步数超过了限定值
        while (d->ht[0].table[d->rehashidx] == NULL)
        {
            d->rehashidx++;
            if (--empty_visits == 0)
                return 1;
        }
        // 终于找到了可搬迁的某个bucket中的 dictEntry
        de = d->ht[0].table[d->rehashidx];

        // 将这个 bucket 中的所有 dictEntry 包括链表上的，前部搬迁到新的 ht[1] 中
        while (de)
        {
            uint64_t h;

            nextde = de->next;
            // 获取当前键值对在新的哈希表中的桶的序号，这里进行取模的是 ht[1]的sizemask，所以 h 很大概率会与在 ht[0] 中的不一样
            h = dictHashKey(d, de->key) & d->ht[1].sizemask;
            // 更新 新桶与旧桶 中的属性
            de->next = d->ht[1].table[h];
            d->ht[1].table[h] = de;
            d->ht[0].used--;
            d->ht[1].used++;
            de = nextde;
        }
        // 搬迁完成，将原来的ht[0]中的bucket置空
        d->ht[0].table[d->rehashidx] = NULL;
        // rehashidx 自增，表示又搬完了一个桶
        d->rehashidx++;
    }

    // 检查是否搬完了整张表
    if (d->ht[0].used == 0)
    {
        // 全部完成搬迁，则释放掉ht[0]的内存，将ht[1]的内容放到ht[0]中，重置ht[1]，并标志rehash完成(rehashidx=-1)
        zfree(d->ht[0].table);
        d->ht[0] = d->ht[1];
        _dictReset(&d->ht[1]);
        d->rehashidx = -1;
        return 0;
    }

    // 否则后面的动作还要继续搬迁
    return 1;
}
```

那什么时候会进行渐进式`rehash`呢？在源码中搜索 `_dictRehashStep`：有以下几处出现了：

1. `dictAddRaw` ：向字典增加一个键值对时；
2. `dictGenericDelete`：查找并移除某个键值对时；
3. `dictFind` ：根据 `key` 查找对应的 `dictEntry` 时；
4. `dictGetRandomKey`：返回一个随机的 `dictEntry` 时；
5. `dictGetSomeKeys`：随机返回指定 `count` 个 `dictEntry` 时，会进行 `count` 次 `_dictRehashStep`

总结一下：

1. 为 `ht[1]` 分配空间， 让字典同时持有 `ht[0]` 和 `ht[1]` 两个哈希表。
2. 在字典中维持一个索引计数器变量 `rehashidx` ， 并将它的值设置为 `0` ， 表示 rehash 工作正式开始。
3. 在 `rehash` 进行期间， 每次对字典执行添加、删除、查找或者更新操作时， 程序除了执行指定的操作以外， 还会顺带将 `ht[0]` 哈希表在 `rehashidx` 索引上的所有键值对 rehash 到 `ht[1]` ， 当 `rehash` 工作完成之后， 程序将 `rehashidx` 属性的值增一。
4. 随着字典操作的不断执行， 最终在某个时间点上， `ht[0]` 的所有键值对都会被 rehash 至 `ht[1]` ， 这时程序将 `rehashidx` 属性的值设为 `-1` ， 表示 `rehash` 操作已完成。

**渐进式 `rehash` 的好处在于它采取分而治之的方式， 将 `rehash` 键值对所需的计算工作均滩到对字典的每个添加、删除、查找和更新操作上， 从而避免了集中式 `rehash` 而带来的庞大计算量**。

#### 3.5 API

- **添加键值对 `dictAdd`**

在上面讲 `rehash` 时，使用的例子，就是 添加键值对，这里不再赘述。

- **删除键值对 `dictDelete`**

其底层调用的是 `dictGenericDelete`：

```c
// 找到key对应的键值对，并移除它。此处dictDelete 调用时传入 nofree=0
static dictEntry *dictGenericDelete(dict *d, const void *key, int nofree)
{
    uint64_t h, idx;
    dictEntry *he, *prevHe;
    int table;

    // 如果字典中键值对数量为0，返回 未找到
    if (d->ht[0].used == 0 && d->ht[1].used == 0)
        return NULL;

    // 如果当前处于 rehash 阶段，则往前进行一步 rehash
    if (dictIsRehashing(d))
        _dictRehashStep(d);

    h = dictHashKey(d, key);

    for (table = 0; table <= 1; table++)
    {
        // 获取桶的索引
        idx = h & d->ht[table].sizemask;
        // 获取桶中的第一个 dictEntry
        he = d->ht[table].table[idx];
        prevHe = NULL;
        // 遍历链表，找到之后将其从链表中删除
        while (he)
        {
            if (key == he->key || dictCompareKeys(d, key, he->key))
            {
                if (prevHe)
                    prevHe->next = he->next;
                else
                    d->ht[table].table[idx] = he->next;
                if (!nofree)
                {
                    dictFreeKey(d, he);
                    dictFreeVal(d, he);
                    zfree(he);
                }
                d->ht[table].used--;
                return he;
            }
            prevHe = he;
            he = he->next;
        }
        // 如果没有再 rehash，就没必要再去 ht[1] 中寻找了
        if (!dictIsRehashing(d))
            break;
    }
    return NULL; // 没找到，返回 NULL
}
```

- **查找键值对 `dictFind`**

过程跟 `dictGenericDelete` 一模一样， `dictGenericDelete` 还多了一个删除操作。

### 4. 跳表

会有专门的一篇文章来讲。看这里：[跳表原理以及 Golang 实现](https://jemmyh.github.io/2020/10/05/tiao-biao/)

### 5. 整数集合

当一个集合中只包含整数，并且元素的个数不是很多的话，redis 会用整数集合作为底层存储，它的一个优点就是可以节省很多内存，虽然字典结构的效率很高，但是它的实现结构相对复杂并且会分配较多的内存空间。当然，当整数集合中的 **元素太多(redis.conf 中 `set-max-intset-entries=512`)** 或者 **添加别的类型的元素**是，整个整数集合会被转化成 **字典**。

> 源码文件：[intset.h](https://github.com/redis/redis/blob/unstable/src/intset.h)

#### 5.1 数据结构

**整数集合（`intset`）** 是 `Redis` 用于保存整数值的集合抽象数据结构， 它可以保存类型为 `int16_t` 、 `int32_t` 或者 `int64_t` 的整数值， 并且保证集合中不会出现重复元素。

```c
typedef struct intset {
    // 编码方式
    uint32_t encoding;

    // 集合中包含的元素数量
    uint32_t length;

    // 保存元素的数组
    int8_t contents[];
} intset;
```

`contents` 数组中的元素按照从小到大的顺序排列，并且保证没有重复值；`length` 表示整数集合中包含的元素数量，即 `contents` 数组的长度。虽然 `contents` 数组的类型是 `int8_t`，但实际上并不保存 `int8_t` 类型的值，而是会根据实际 `encoding` 的值做出判断，比如 `encoding = INTSET_ENC_INT16`，那么数组的底层类型均为 `int16_t` ，整个数组中的元素类型都是 `int16_t`：

```c
/* Note that these encodings are ordered, so:
 * INTSET_ENC_INT16 < INTSET_ENC_INT32 < INTSET_ENC_INT64. */
#define INTSET_ENC_INT16 (sizeof(int16_t))  // int16 16位
#define INTSET_ENC_INT32 (sizeof(int32_t))  // int32 32位
#define INTSET_ENC_INT64 (sizeof(int64_t))  // int64 64位

// 返回 v 对应的 encoding 值
static uint8_t _intsetValueEncoding(int64_t v) {
    if (v < INT32_MIN || v > INT32_MAX)
        return INTSET_ENC_INT64;
    else if (v < INT16_MIN || v > INT16_MAX)
        return INTSET_ENC_INT32;
    else
        return INTSET_ENC_INT16;
}
```

下面是一个使用 `INTSET_ENC_INT16` 编码的、长度为 6 的整数集合：

![整数集合举例](https://pic.downk.cc/item/5f788aa8160a154a6719f5d2.png)

#### 5.2 API

- **初始化 `intset`**

```c
// 创建一个空的 intset
intset *intsetNew(void) {
    // 为 intset 对象申请空间
    intset *is = zmalloc(sizeof(intset));
    // 默认使用 INTSET_ENC_INT16 作为存储大小
    is->encoding = intrev32ifbe(INTSET_ENC_INT16);
    // 数组长度为0，因为没有初始化的操作
    is->length = 0;
    return is;
}
```

这里有一点需要注意，创建 `intset` 的时候并没有初始化 `contents` 数组，应为没必要。在常规情况下，访问数组是根据数组第一个元素地址加上类型大小作为偏移值读取，但是 `intset` 的数据类型依赖于 `encoding`，读取的时候通过 `memcpy` 按照 `encoding` 的值重新计算偏移量暴力读取的，属于 非常规操作数据，因此，刚开始没必要申请数组的空间，等添加一个元素时，动态扩容该元素的大小的内存即可。

- **添加元素**

我们先看代码：

```c
// 在 intset 中添加一个整数
intset *intsetAdd(intset *is, int64_t value, uint8_t *success) {
    uint8_t valenc = _intsetValueEncoding(value);  // 根据要插入的 value 的类型 获取对应的 encoding
    uint32_t pos;
    if (success) *success = 1;  // success = NULL

    if (valenc > intrev32ifbe(is->encoding)) {
        // 插入元素的 encoding 值大于 intset 当前的，升级
        return intsetUpgradeAndAdd(is,value);
    } else {
        // 插入元素的 encoding 值小于等于当前 intset 的，则找到这个 value 应该插入的位置，赋值给 pos，已经存在的话直接返回
        if (intsetSearch(is,value,&pos)) {
            if (success) *success = 0;
            return is;
        }

        // 动态扩容
        is = intsetResize(is,intrev32ifbe(is->length)+1);
        // 将 pos 位置后面的元素整体向后挪一位，给 pos 腾位置
        if (pos < intrev32ifbe(is->length)) intsetMoveTail(is,pos,pos+1);
    }

    // 将 pos 位置设置为 value
    _intsetSet(is,pos,value);
    // 更新 length
    is->length = intrev32ifbe(intrev32ifbe(is->length)+1);
    return is;
}

// 动态扩容，即将原来数组的容量 (is.length*encoding) 调整为 ((is.length+1)*encoding)
static intset *intsetResize(intset *is, uint32_t len) {
    uint32_t size = len*intrev32ifbe(is->encoding);
    is = zrealloc(is,sizeof(intset)+size);
    return is;
}

// 暴力迁移pos位置之后的数据，为pos位置挪出位置
static void intsetMoveTail(intset *is, uint32_t from, uint32_t to) {
    // from = pos, to = pos+1

    // src 表示 pos 相对于数组头部的迁移量
    // dst 表示 pos下一个元素相对于数组头部的偏移量
    void *src, *dst;
    // pos位置 距离数组末尾的元素个数，bytes*类型大小 即是pos后面的所有元素的总长度
    uint32_t bytes = intrev32ifbe(is->length)-from;
    // encoding
    uint32_t encoding = intrev32ifbe(is->encoding);

    if (encoding == INTSET_ENC_INT64) {
        src = (int64_t*)is->contents+from;
        dst = (int64_t*)is->contents+to;
        bytes *= sizeof(int64_t);
    } else if (encoding == INTSET_ENC_INT32) {
        src = (int32_t*)is->contents+from;
        dst = (int32_t*)is->contents+to;
        bytes *= sizeof(int32_t);
    } else {
        src = (int16_t*)is->contents+from;
        dst = (int16_t*)is->contents+to;
        bytes *= sizeof(int16_t);
    }
    // 从 src 复制 bytes 个字符到 dst
    memmove(dst,src,bytes);
}
```

整个过程可以简单总结为：先判断当前插入值的 `encoding` 是否超过了 `intset` 的，如果超过了，进行升级，**升级** 操作我们待会儿再看。没超过的话，需要找到当前元素应该插入的位置 `pos` ，**查找** 操作我们还是待会儿再看。之后是动态扩容，动态扩容的过程有：先将数组容量增加，之后将 `pos` 后面的元素整体移一位，最后将 `value` 值写入 `pos` 处。特别需要注意的是，**将 `pos` 后面的元素整体后移一位** 这一步，没有逐个移动元素，而是计算好 `src` 和 `dst`，直接调用 `memmove` 将 `src` 处的 `bytes` 个字符复制到 `dst` 处，这正是利用了 `intset` 数组非常规读取数组的特点。下面通过一个例子看一下插入的过程：

![intset插入元素](https://pic.downk.cc/item/5f789ebf160a154a671f936b.png)

- **升级**

当插入的元素的类型比集合中现有所有元素的类型都要长时，需要先将数组整个升级之后，才能继续插入元素。**升级** 指的是 将数组类型变成和插入值类型相同的过程。

升级过程大致可分为三个步骤：

1. 根据新元素类型，扩展底层数组的大小，并为新元素分配空间；
2. 将底层数组的所有元素都转化成与新元素相同，并将转换后的元素放在合适的位置上，并且在防止的过程中，需要维持底层数组中数组顺序不变；
3. 将新元素添加到新数组中

下面我们直接看代码：

```c
static intset *intsetUpgradeAndAdd(intset *is, int64_t value) {
    uint8_t curenc = intrev32ifbe(is->encoding);  // 当前 encoding
    uint8_t newenc = _intsetValueEncoding(value); // 插入元素的 encoding
    int length = intrev32ifbe(is->length);
    // 插入到 数组最左边 还是 数组最右边。为什么会是最值？因为要升级，所以插入值肯定超出了现有 encoding 对应类型的最值，要么是负数越界，要么是正数越界
    int prepend = value < 0 ? 1 : 0;

    // 首先，设置 intset 的 encoding 为插入元素的 encoding(更大的那个)
    is->encoding = intrev32ifbe(newenc);
    // 根据新元素类型 扩展数组大小
    is = intsetResize(is,intrev32ifbe(is->length)+1);

    // 从数组最后一个元素开始遍历，将其放入合适的位置。prepend 的作用就是确保我们能给待插入值留下最左边的位置 或 最右边的位置
    while(length--)
        _intsetSet(is,length+prepend,_intsetGetEncoded(is,length,curenc));

    // 在数组头部或者数组尾部插入 value
    if (prepend)
        _intsetSet(is,0,value);
    else
        _intsetSet(is,intrev32ifbe(is->length),value);
    // 最后更新 length
    is->length = intrev32ifbe(intrev32ifbe(is->length)+1);
    return is;
}
```

通过一个例子说明升级的过程：

![整数集合升级](https://tva1.sinaimg.cn/large/007S8ZIlgy1gjcm49s2sfj30nn0tmk4v.jpg)

注意：整数集合没有降级操作！一旦对数组进行了升级， 编码就会一直保持升级后的状态。

- **查找**

在 `intset` 中查找 `value` 是否存在，如果存在，返回 1，同时将 `pos` 值设置为数组的索引值；如果不存在，返回 0，同时将 `pos` 设置成应该存放的位置的索引值：

```c
static uint8_t intsetSearch(intset *is, int64_t value, uint32_t *pos) {
    int min = 0, max = intrev32ifbe(is->length)-1, mid = -1;
    int64_t cur = -1;

    // 当 intset 中没有元素时，直接返回
    if (intrev32ifbe(is->length) == 0) {
        if (pos) *pos = 0;
        return 0;
    } else {
        // 大于当前数组中最大值 或 小于最小值，也是直接返回
        if (value > _intsetGet(is,max)) {
            if (pos) *pos = intrev32ifbe(is->length);
            return 0;
        } else if (value < _intsetGet(is,0)) {
            if (pos) *pos = 0;
            return 0;
        }
    }

    // 因为数组有序，所以采用二分法查找位置是一个非常正确的选择
    while(max >= min) {
        mid = ((unsigned int)min + (unsigned int)max) >> 1;
        cur = _intsetGet(is,mid);
        if (value > cur) {
            min = mid+1;
        } else if (value < cur) {
            max = mid-1;
        } else {
            break;
        }
    }

    if (value == cur) {
        // value 已经存在
        if (pos) *pos = mid;
        return 1;
    } else {
        // value 不存在
        if (pos) *pos = min;
        return 0;
    }
}
```

#### 5.3 总结

- 整数集合的底层实现为数组， 这个数组以有序、无重复的方式保存集合元素， 在有需要时， 程序会根据新添加元素的类型， 改变这个数组的类型。
- 升级操作为整数集合带来了操作上的灵活性， 并且尽可能地节约了内存。
- 整数集合只支持升级操作， 不支持降级操作。
- 整数集合中的元素不能太对，当超过配置值后，会被转化成字典。

### 6. 压缩列表

**压缩列表** 是 `Redis` 自己实现的一个数据存储结构，有点类似数组，通过一片连续的空间存储数据，只不过数组的每个元素大小都相同，压缩列表允许每个元素有自己的大小。其核心思想，就是在一个连续的内存上，模拟出一个链表的结构。

在源代码中有这么一段描述：

> The ziplist is a specially encoded dually linked list that is designed to be very memory efficient. It stores both strings and integer values, where integers are encoded as actual integers instead of a series of characters. It allows push and pop operations on either side of the list in O(1) time. However, because every operation requires a reallocation of the memory used by the ziplist, the actual complexity is related to the amount of memory used by the ziplist.

大致意思是：`ziplist` 是一个**经过特殊编码的双向链表**，它的设计目标就是为了**提高存储效率**。`ziplist` 可以用于存储字符串或整数，其中整数是按真正的二进制表示进行编码的，而不是编码成字符串序列。它能以 `O(1)` 的时间复杂度在表的两端提供 `push` 和 `pop` 操作。但由于每次操作都需要重新分配 `ziplist` 使用的内存，所以实际的复杂度与 `ziplist` 使用的内存量有关。

> 源码文件：[ziplist.h](https://github.com/redis/redis/blob/unstable/src/ziplist.h)

#### 6.1 数据结构

`ziplist` 并没有实际的 `struct` 表示，但在 `ziplist.c` 中有如下描述：

> The general layout of the ziplist is as follows:
>
> **\<zlbytes> \<zltail> \<zllen> \<entry> \<entry> ... \<entry> \<zlend>**
>
> - `zlbytes`：本身占用 4 字节，整个压缩列表占用的总字节数(包括他自己)
> - `zltail`：本身占用 4 字节，起始位置到最后一个结点的偏移量，用来快速定位最后一个元素，在反向输出压缩列表时会有用
> - `zllen`：本身占用 2 字节，压缩列表包含的元素个数
> - `entry`：元素内容。用数组存储，内存上紧挨着
> - `zlend`：本身占用 1 字节，压缩列表结束的标志位，一般为常量 `0xFF`

接下来看 `entry` 这个结构：

> **\<prevlen> \<encoding> \<entry-data>**
>
> - `prevlen`：1 字节或者 5 字节，表示前一个 `entry` 长度，在反向遍历的时候会有用
> - `encoding`：1、2 或 5 字节，表示当前 `entry` 的编码方式，表示当前 `entry` 的类型，`integer` 或 `string`
> - `entry-data`：实际所需的字节数，结点真正的值，可以是 `integer` 或 `string`。它的类型和长度由 `encoding` 来决定

接下来我们详细关注这三个参数：

##### `prevlen`

以字节为单位，记录前一个 `entry` 的长度。`prevlen` 的长度可以是 **1 字节** 或者 **5 字节**：

- 当前一个结点的长度小于 254 字节时，`prevlen` 的长度为 **1 字节**，前一个 `entry` 的长度就保存在这一个字节中；
- 当前一个结点的长度大于等于 254 字节时，`prevlen` 的长度为 **5 字节**，其中第一个字节会被设置成 `0xFE`(十进制的 `254`)，表示这是一个 **5 字节长** 的 `prevlen`，后面的四个字节则保存前一个 `entry` 的长度。

`prevlen` 的作用是：在反向遍历压缩数组时，可以通过当前元素的指针，减去 `prevlen` ，就能得到前一个元素的地址。

![](https://pic.downk.cc/item/5f78e315160a154a672db33d.png)

##### `encoding`

节点的 `encoding` 属性记录了节点的 `entry-data` 属性所保存 **数据的类型** 以及 **长度**：

- 一字节、两字节或者五字节长， 值的最高位为 `00` 、 `01` 或者 `10` 的是**字节数组编码**： 这种编码表示节点的 `content` 属性保存着 **字符串(字节数组)**， 数组的长度由编码除去最高两位之后的其他位记录：

| 编码                         |  编码长度  |                            content 中保存的值                             |
| :--------------------------- | :--------: | :-----------------------------------------------------------------------: |
| 00bbbbbb                     | **1 字节** |     长度小于等于 63 字节的字节数组(6 位分辨位，2^6 = 64，除去全 0 的)     |
| 01bbbbbb \| xxxxxxxx         | **2 字节** | 长度小于等于 16383 字节的字节数组(14 位分辨位，2^14 = 16384，除去全 0 的) |
| 10000000 \| xxxx…xxxx(32 位) | **5 字节** |  长度小于等于 4294967295 字节的字节数组(32 位分辨位，2^32 = 4294967296)   |

- 一字节长， 值的最高位以 `11` 开头的是**整数编码**： 这种编码表示节点的 `entry-data` 属性保存着**整数**值， 整数值的类型和长度由编码除去最高两位之后的其他位记录:

| 编码     | 编码长度 |                                                                 entry-data 中保存的值                                                                 |
| :------- | :------: | :---------------------------------------------------------------------------------------------------------------------------------------------------: |
| 11000000 |  1 字节  |                                                                   int16_t 类型整数                                                                    |
| 11010000 |  1 字节  |                                                                   int32_t 类型整数                                                                    |
| 11100000 |  1 字节  |                                                                   int64_t 类型整数                                                                    |
| 11110000 |  1 字节  |                                                                    24 位有符号整数                                                                    |
| 11111110 |  1 字节  |                                                                    8 位有符号整数                                                                     |
| 1111xxxx |  1 字节  | 使用这一编码的节点没有相应的 `entry-data` 属性， 因为编码本身的 `xxxx` 四个位已经保存了一个介于 `0` 和 `12` 之间的值， 所以它无须 `entry-data` 属性。 |

##### `entry-data`

节点的 `entry-data` 属性负责保存节点的值， 节点值可以是一个字节数组或者整数， 值的类型和长度由节点的 `encoding` 属性决定。

![](https://pic.downk.cc/item/5f78e80c160a154a672e5400.png)

![压缩列表-示例](https://pic.downk.cc/item/5f796b73160a154a674807ff.png)

#### 6.2 API

- **创建`ziplist`**

返回一个只包含 `<zlbytes><zltail><zllen><zlend>` 的 `ziplist`：

```c
unsigned char *ziplistNew(void) {
    unsigned int bytes = ZIPLIST_HEADER_SIZE+ZIPLIST_END_SIZE;  // 头部的 4+4+2 和 尾部的1 总共 11 字节
    unsigned char *zl = zmalloc(bytes);  // 这里的ziplist类型是一个 char 数组，而不是某个具体的结构体
    ZIPLIST_BYTES(zl) = intrev32ifbe(bytes);  // 设置 zlbytes 为 初始分配的值，即 bytes
    ZIPLIST_TAIL_OFFSET(zl) = intrev32ifbe(ZIPLIST_HEADER_SIZE);  // 设置 zltail 为 header 结束的地方
    ZIPLIST_LENGTH(zl) = 0;  // 设置 zllen 为 0
    zl[bytes-1] = ZIP_END;  // 最后一个字节存储常量 255 ，表示 ziplist 结束
    return zl;
}
```

- **插入`ziplistInsert`**

这个函数的作用是 **在 `ziplist` 的任意数据项前面插入一个新的数据项**：

```c
unsigned char *ziplistInsert(unsigned char *zl, unsigned char *p, unsigned char *s, unsigned int slen) {
    return __ziplistInsert(zl,p,s,slen);
}

// 在 p 处 插入 s，s 的长度为 slen；插入后s占据p的位置，p及其后面的数据整体后移。其中 p 指向 ziplist 中某一个 entry 的起始位置，或者 zlend(当向尾部插入时)
unsigned char *__ziplistInsert(unsigned char *zl, unsigned char *p, unsigned char *s, unsigned int slen) {
	// reqlen 表示 将 s 变成一个 entry 所需要的总字节数，即 prevlen,encoding,entry-data 的总长度
    size_t curlen = intrev32ifbe(ZIPLIST_BYTES(zl)), reqlen;
    unsigned int prevlensize, prevlen = 0;
    size_t offset;
    int nextdiff = 0;
    unsigned char encoding = 0;
    long long value = 123456789; // 随便使用一个一眼就能看出来的值表示当前变量未被逻辑初始化，避免 warning
    zlentry tail;

    if (p[0] != ZIP_END) {
        // 如果不是插入尾部，则根据p获取 p所在的 entry 的前一个 entry 的 prevlen，需要保存 prevlen的字节数保存在 prevlensize(1字节或者5字节，前面有介绍)
        ZIP_DECODE_PREVLEN(p, prevlensize, prevlen);
    } else {
        // p 指向的是 尾部标志
        unsigned char *ptail = ZIPLIST_ENTRY_TAIL(zl);
        if (ptail[0] != ZIP_END) {
            // 获取 ziplist 最后一个 entry 的长度，保存在 prevlen 中
            prevlen = zipRawEntryLength(ptail);
        }
    }

    // 尝试能否转化成整数
    if (zipTryEncoding(s,slen,&value,&encoding)) {
        // 可以转化成 int，则 reqlen 即为存储此 int 所需的字节数，即 entry-data 的长度
        reqlen = zipIntSize(encoding);
    } else {
        // 无法转换成 int，那就是字节数组，reqlen 就是要存入的字符串的长度，即 entry-data 的长度
        reqlen = slen;
    }

    // reqlen
    reqlen += zipStorePrevEntryLength(NULL,prevlen);  // 再加上 prevlen 的长度
    reqlen += zipStoreEntryEncoding(NULL,encoding,slen);  // 再加上 encoding 的长度

    // 当不是向尾部插入时，我们必须确保下一个 entry 的 prevlen 等于当前 entry 的长度
    int forcelarge = 0;
    // 【1】nextdiff 存储的是p的prevlen的变化值(新元素长度reqlen - p之前entry的prelen)，具体解释看代码后面【1】处的解释
    nextdiff = (p[0] != ZIP_END) ? zipPrevLenByteDiff(p,reqlen) : 0;
    if (nextdiff == -4 && reqlen < 4) {
        nextdiff = 0;
        forcelarge = 1;  // 这种情况下意味着，本来可以用 1 字节的，却使用了 5 个字节
    }

    /* Store offset because a realloc may change the address of zl. */
    // 存储 p 相对于 ziplist 的偏移量，因为 resize 可能改变 ziplist 的起始地址
    offset = p-zl;
    // 到这一步已经能确定 ziplist 需要的总的容量了，调用 resize 调整 ziplist 的大小
    zl = ziplistResize(zl,curlen+reqlen+nextdiff);
    // 重新定位 p
    p = zl+offset;

    // 将 p 以及其后面的数据移动为 s 挪地方，别忘了更新 zltail 的值
    if (p[0] != ZIP_END) {

        // 在p前面腾出reqlen字节给新entry使用（将p move到p+reqlen，考虑了prelen缩减或增加）
        memmove(p+reqlen,p-nextdiff,curlen-offset-1+nextdiff);

        // 更新 s 的后一个 entry（p+reqlen即p的新地址）的prevlen；
        if (forcelarge)
            // 【2】强制使用 5 字节存储，避免连锁更新时的大量重新分配空间操作，不进行缩容
            zipStorePrevEntryLengthLarge(p+reqlen,reqlen);
        else
            // 计算 reqlen 进而判断使用 1 字节 还是 5 字节
            zipStorePrevEntryLength(p+reqlen,reqlen);

        // 更新 zltail
        ZIPLIST_TAIL_OFFSET(zl) =
            intrev32ifbe(intrev32ifbe(ZIPLIST_TAIL_OFFSET(zl))+reqlen);

          // 更新zltail
        zipEntry(p+reqlen, &tail);
        if (p[reqlen+tail.headersize+tail.len] != ZIP_END) {
            ZIPLIST_TAIL_OFFSET(zl) =
                intrev32ifbe(intrev32ifbe(ZIPLIST_TAIL_OFFSET(zl))+nextdiff);
        }
    } else {
        // 如果是在尾部插入，则直接修改 zltail 为 s
        ZIPLIST_TAIL_OFFSET(zl) = intrev32ifbe(p-zl);
    }

    // 如果 nexydiff 不等于0，整个 s 后面的 ziplist 的 prevlen 都可能发生变化，这里尝试进行维护
    if (nextdiff != 0) {
        offset = p-zl;
        zl = __ziplistCascadeUpdate(zl,p+reqlen);
        p = zl+offset;  // 改变的只是 p 后面的，前面的没变，因此 s 插入的位置没变
    }

    // 存入 s 这个 entry
    p += zipStorePrevEntryLength(p,prevlen);
    p += zipStoreEntryEncoding(p,encoding,slen);
    if (ZIP_IS_STR(encoding)) {
        memcpy(p,s,slen);
    } else {
        zipSaveInteger(p,value,encoding);
    }
    // ziplist 的长度加 1
    ZIPLIST_INCR_LENGTH(zl,1);
    return zl;
}

// 将 ziplist 的长度变成 len
unsigned char *ziplistResize(unsigned char *zl, unsigned int len) {
    zl = zrealloc(zl,len);
    ZIPLIST_BYTES(zl) = intrev32ifbe(len);
    zl[len-1] = ZIP_END;
    return zl;
}
```

解释【1】：这种情况发生在 **插入的位置不是尾部** 的情况，我们假设 `p` 的前一个元素为 `p0`，此时 `p` 的 `prevlen` 存储的是 `p0` 的长度。但是由于要将 `s` 插入到 `p` 之前，那么 `p` 的 `prevlen` 的值就应该变成 `s` 的长度，这样 `p` 本身的长度也就发生了变化，有可能变大也有可能变小。这个变化了多少的值就是 `nextdiff`，如果变大了，`nextdiff` 是正数，否则是负数。如果是负数，只有一种情况，那就是 `p0` 的长度大于 254，用 5 个字节存；而 `s` 的长度小于 254，用 1 个字节存就够了。

解释【2】：关于 `forcelarge`，这是一个已经被修改后的 [bug](https://github.com/redis/redis/commit/8327b813#diff-b109b27001207a835769c556a54ff1b3)，大致意思是，这种操作发生在 **连锁更新**(90 行) 的时候，为了防止大量的重新分配空间的动作，如果一个 `entry` 的长度只需要 1 个字节就能够保存,但是连锁更新时如果原先已经为 `prevlen` 分配了 5 个字节,则不会进行缩容操作。关于为何，可以参考这篇文章：[Redis 的一个历史 bug 及其后续改进](https://erpeng.github.io/2019/04/15/Redis%E7%9A%84%E4%B8%80%E4%B8%AA%E5%8E%86%E5%8F%B2bug%E5%8F%8A%E5%85%B6%E5%90%8E%E7%BB%AD%E6%94%B9%E8%BF%9B/)，作者对这个 `bug` 进行了复现，以及提到了 `Redis` 对此作出的更新(提出了更优化的结构 `listpack`)。

我们接着说 **连锁更新**。回忆一个 `entry` 的结构，其中 `prevlen` 表示前一个 `entry` 的长度：如果前一个结点长度小于 254，则 `prevlen` 占用 1 字节，否则占用 5 字节。现在， 考虑这样一种情况： 在一个压缩列表中， 有多个连续的、长度介于 `250` 字节到 `253` 字节之间的节点 `e1` 至 `eN` 。因为 `e1` 至 `eN` 的所有节点的长度都小于 `254` 字节， 所以记录这些节点的长度只需要 `1` 字节长的 `prevlen` 属性， 换句话说， `e1` 至 `eN` 的所有节点的 `prevlen` 属性都是 `1` 字节长的。此时，如果我们在 `e1` 前面插入一个长度大于 254 的元素 `m`，因为 `e1` 的 `prevlen` 仅为 1 字节，无法保存大于 254 的数，因此，我们还要对 `ziplist` 进行空间重分配操作，使得 `e1` 能够保存 `m` 的长度，即将 `ziplist` 的大小再增加 4 字节，让 `e1` 的 `prevlen` 大小由 1 字节变为 5 字节，这种操作我们称为 `m` 对 `e1` 发生了 **扩展**。回到刚才的情况，现在麻烦来了，`e1` 大小发生了变化，肯定超过了原来的 254，此时 `e1` 需要对 `e2` 进行扩展，又到后面，`e2` 需要对 `e3` 进行扩展……程序需要不断地对压缩列表执行空间重分配操作， 直到 `eN` 为止。

`Redis` 将这种在特殊情况下产生的连续多次空间扩展操作称之为 **“连锁更新”（`cascade update`）**。我们看看 **连锁更新** 的具体实现：

```c
// p 指向第一个不需要更新的 entry
unsigned char *__ziplistCascadeUpdate(unsigned char *zl, unsigned char *p) {
    size_t curlen = intrev32ifbe(ZIPLIST_BYTES(zl)), rawlen, rawlensize;
    size_t offset, noffset, extra;
    unsigned char *np;
    zlentry cur, next;

    // 当 p 是 ziplist 的”尾巴“时停止更新
    while (p[0] != ZIP_END) {
        zipEntry(p, &cur);  // 【1】将 entry 解码称为一个易于操作的 entry 结构体，细节见代码后解释
        rawlen = cur.headersize + cur.len; // 当前节点的长度
        rawlensize = zipStorePrevEntryLength(NULL,rawlen);  // 存储当前节点所需要的 prevlen 大小

        // 没有下一个节点，直接返回
        if (p[rawlen] == ZIP_END) break;

        // 获取 p 的下一个节点
        zipEntry(p+rawlen, &next);

        // 如果下一个节点的 prevlen 等于当前节点的 长度，则没必要更新，直接退出循环
        if (next.prevrawlen == rawlen) break;

        // 下一个节点的 prevlen 小于当前节点的长度(当前节点长度为 5 字节，next 的 prevlen 为1 字节)
        if (next.prevrawlensize < rawlensize) {

            // ziplist的地址可能发生改变，先记录 p 相对于zl起始位置的偏移量
            offset = p-zl;
            // 额外需要申请的空间 5 - 1 = 4
            extra = rawlensize-next.prevrawlensize;
            // 改变 ziplist 的容量
            zl = ziplistResize(zl,curlen+extra);
            // 重新计算 p 的位置
            p = zl+offset;

            /* Current pointer and offset for next element. */
            np = p+rawlen;  // next 的新地址
            noffset = np-zl;  // next新地址相对于 ziplist 头部的偏移量

            // 更新 zltail
            if ((zl+intrev32ifbe(ZIPLIST_TAIL_OFFSET(zl))) != np) {
                ZIPLIST_TAIL_OFFSET(zl) =
                    intrev32ifbe(intrev32ifbe(ZIPLIST_TAIL_OFFSET(zl))+extra);
            }

            // 扩展 next 的 prevlen，并将数据拷贝
            memmove(np+rawlensize,
                np+next.prevrawlensize,
                curlen-noffset-next.prevrawlensize-1);
            // 在扩展后的 next 的 prevlen 中重新记录 p 的长度
            zipStorePrevEntryLength(np,rawlen);

            /* Advance the cursor */
            // 更新 p 为下一个 entry
            p += rawlen;
            // 更新 p 的长度(需要加上扩展的 prevlen 的 extra 个字节)
            curlen += extra;
        } else {
            // 这种情况下，next 的 prevlen 足够表示 当前 p 的长度
            if (next.prevrawlensize > rawlensize) {
                // next 的 prevlen > p 的长度(next.prevlen = 5 结点，p的长度小于 5 个结点)，此时应该 缩容，但出于性能以及操作的方便性(减少后续连锁更新的可能性)，我们通常不进行缩容，这个时候，直接将 next 的 prevlen 设置为 5 个结点
                zipStorePrevEntryLengthLarge(p+rawlen,rawlen);
            } else {
                // 相等
                zipStorePrevEntryLength(p+rawlen,rawlen);
            }

            // next 的长度并没有发生变化(没有缩容)，终止循环
            break;
        }
    }
    return zl;
}
```

解释【1】：“辅助结构体” `zlentry`，这个结构体与 `ziplist` 中的一个实际 `entry` 相对应，其作用是为了更加方便地操作一个 实际的 `entry`：

```c
typedef struct zlentry {
    unsigned int prevrawlensize; // 存储 prevrawlen 所需要的字节数，同样也有 1字节 和 5字节之分
    unsigned int prevrawlen;     // 对应 prevlen
    unsigned int lensize;        // 存储 len 所需要的字节数
    unsigned int len;            // 当前 entry 的长度
    unsigned int headersize;     // ziplist头部大小: prevrawlensize + lensize
    unsigned char encoding;      // 编码方式
    unsigned char *p;            // 指向某个实际 entry 的地址
} zlentry;
```

**其他的一些操作，比如删除、查找，过程与插入类似，无非就是各个 entry 地址的计算，删除时还有可能涉及到连锁更新。** 这里不再描述，想了解的可以根据上面的思路自己研究源代码。

#### 6.3 总结

- `ziplist`是 redis 为了节省内存，提升存储效率自定义的一种紧凑的数据结构，每一个 `entry` 都保存这上一个 `entry` 的长度，可以很方便地进行反向遍历；
- 添加和删除节点可能会引发连锁更新，极端情况下会更新整个`ziplist`，但是概率很小；
- 在 `Redis` 中，当元素个数较少时，哈希表(`hset` 等操作) 和 列表(`lpush` 等操作) 的底层结构都是 `ziplist`。

### 7. 紧凑列表

> 源码文件：[listpack.h](https://github.com/redis/redis/blob/unstable/src/listpack.h)
>
> 实现文档：[Listpack specification](https://gist.github.com/antirez/66ffab20190ece8a7485bd9accfbc175)

紧凑列表是 压缩列表 的升级版，目的是在未来代替 `ziplist`。

有时间再完善。

## 二、 `Redis` 对象对应的数据结构

前面大致介绍了 **简单动态字符串 `sds`**、**双端链表 `adlist`**、**字典 `dict`**、**跳表 `skiplist`**、**整数集合 `intset`** 和 **压缩列表 `ziplist`** 等基础数据结构，同时我们知道 `Redis` 中有 **字符串对象(string)**、**列表对象(list)**、**哈希对象(hash)**、**集合对象(set)** 和 **有序集合对象(zset)** 等五种对象，他们都至少用了上面一种基础数据结构来实现。在 `Redis` 中，客户端的一条命令以及参数会被解释成一个 `robj` 结构体：

> 源码文件： [server.h](<[ziplist.h](https://github.com/redis/redis/blob/unstable/src/server.h)>)

```c
typedef struct redisObject
{
    unsigned type : 4;       // 类型
    unsigned encoding : 4;	 // 编码
    unsigned lru : LRU_BITS; // 对象最后被访问的时间，我们暂时不关注 LRU
    int refcount;			 // 引用次数
    void *ptr;				 // 指向实现对象的数据结构
} robj;

/* Object types */
#define OBJ_STRING 0 /* String object. */
#define OBJ_LIST 1   /* List object. */
#define OBJ_SET 2    /* Set object. */
#define OBJ_ZSET 3   /* Sorted set object. */
#define OBJ_HASH 4   /* Hash object. */

/* Objects encoding. Some kind of objects like Strings and Hashes can be
 * internally represented in multiple ways. The 'encoding' field of the object
 * is set to one of this fields for this object. */
#define OBJ_ENCODING_RAW 0        // 简单动态字符串 sds
#define OBJ_ENCODING_INT 1        // long 类型
#define OBJ_ENCODING_HT 2         // 字典 dict
#define OBJ_ENCODING_ZIPMAP 3     // zipmap(弃用)
#define OBJ_ENCODING_LINKEDLIST 4 // 双端链表 adlist
#define OBJ_ENCODING_ZIPLIST 5    // 压缩列表 ziplist
#define OBJ_ENCODING_INTSET 6     // 整数集合 intset
#define OBJ_ENCODING_SKIPLIST 7   // 跳表 skiplist
#define OBJ_ENCODING_EMBSTR 8     // 采用embstr编码的sds
#define OBJ_ENCODING_QUICKLIST 9  // qunicklist，用于列表
#define OBJ_ENCODING_STREAM 10    // 紧凑列表 listpack
#define LRU_BITS 24
```

`obj` 的作用大致为：

- 为多种数据类型提供一种统一的表示方式。
- 允许同一类型的数据采用不同的内部表示，从而在某些情况下尽量节省内存。
- 支持对象共享和引用计数。当对象被共享的时候，只占用一份内存拷贝，进一步节省内存。

说到底， `robj` 所表示的就是 **五种 `Object types`** 和 **11 中 `Object encoding`** 之间的对应方式，起到一个桥梁作用。这种对应关系可用如下的图来表示：

![Redis对象与数据结构对应关系](https://pic.downk.cc/item/5f7a3a91160a154a67813577.png)
