---
title: "Boltdb使用(一)基本用法"
date: 2021-01-05T16:28:43+08:00
draft: false
author: JemmyHu(hujm20151021@gmail.com)
toc: true
mathjax: true
categories: [技术博客, 技术细节, Golang, bolt]
tags: [Golang, bolt]
---

## 介绍

[boltdb](https://github.com/boltdb/bolt) 是一个使用 Go 编写的键值对数据库，它的目标是 **简单、快速和稳定的轻型数据库**，适用于那些不需要使用像 MySQL 一样的完整的数据库系统的项目。

## 使用

### 1. 安装

```bash 
go get github.com/boltdb/bolt/...
```

### 2. 打开(Open)一个数据库文件连接

```go
func main() {
    dbPath := "./data.db"  // 指定你的数据库文件要存储的地方
    db, err := bolt.Open(dbPath, os.ModePerm, nil)
	if err != nil {
		panic(err)
    }
    ...
}
```

> `bolt` 打开一个文件之后，会一直获得此文件的锁，在这期间，其他的进程无法再次打开此文件，直到最开始的进程释放锁。打开一个已经打开的 bolt文件 会导致当前进程无限制地等待下去，直到另一个已经打开的进程结束这个文件的使> 用。为了避免这种无限制的等待，可以给 `Open` 操作添加超时：
>
> ```go
> db, err := bolt.Open(dbPath, os.ModePerm, &bolt.Options{Timeout: time.Second * 5})
> ```
>
> 运行如上代码，如果 5 秒内未能成功打开文件，会返回一个 `timeout` 错误。

### 3. 事务(Transaction)

在某一时刻， `bolt` **只允许有一个读写事务** 或者 **允许多个只读事务**。其事务的隔离级别对应 `MySQL` 中的 **可重复读**，即每一个事务在 `commit` 之前，多次读库多看到的信息视图是一致的。

#### 3.1 读写事务(Read-write Transactions)

启动一个 读写事务，可以通过下面的方式：

```go
err := db.Update(func(tx *bolt.Tx) error {
    ...
    return nil
}) 
if err != nil {
    log.Fatal(err)
}
```

或者：

```go
// open a Read-write transaction with the first argument `true`
tx,err := db.Begin(true)
if err != nil {
    log.Fatal(err)
}
defer tx.Rollback()
// do something ...

// commit the transaction
if err := tx.Commit();err != nil {
    log.Fatal(err)
}
```

`Update` 中的函数就是一个 **可重复读** 的事务，在这个函数里面可以进行任何的数据库操作。最后需要通过 `return nil` 来提交修改；如果提交一个 `error`，那么整个修改会进行 `Rollback`，回到最初的状态，不会产生任何改变。注意，在 `Update` 中手动进行 `Rollback`，会造成 `panic`。

#### 3.2 只读事务(Read-only Transactions)

通过下面的方式打开一个只读事务：

```go
err := db.View(func(tx *bolt.Tx) error {
    ...
    return nil
})
```

或者：

```go
// open a Read-only transaction with the first argument `false`
tx,err := db.Begin(false)
if err != nil {
    log.Fatal(err)
}
defer tx.Rollback()
// do something ...

// commit the transaction
if err := tx.Commit();err != nil {
    log.Fatal(err)
}
```

需要注意的是，在 `View` 只读事务中，无法做一些“写入”操作，能做的可以是：读一个 bucket，读对应 bucket 中的值，或者复制整个 db。注意，在 `View` 中手动进行 `Rollback`，会造成 `panic`。

#### 3.3 批量读写事务(Batch read-write transactions)

通过以下方式使用 `Batch`：

```go
err := db.Batch(func(tx *bolt.Tx) error {
    b := tx.Bucket(bucketName)

    for i := 0; i < 100; i++ {
        if err := b.Put([]byte(fmt.Sprintf("name-%d", i+1)), []byte(fmt.Sprintf("%d", rand.Int31n(math.MaxInt32)))); err != nil {
            return err
        }
    }

    return nil
})
```

`Batch` 和 `Update` 相似，以下情形除外：

1. `Batch` 中的操作可以被合并成一个 transaction；
2. 传给 `Batch` 的函数可能被执行多次，不管返回的 `error` 是否为 `nil`

这也就意味着，`Batch` 里面的操作必须是幂等的，这似乎会带来一些额外的工作，因此之建议在 多个 goroutine 同时调用的时候使用。

创建一个 `DB` 对象是线程安全的，但一个事务里面的操作并不是线程安全的。另外，`读写事务` 和 `只读事务` **不应该相互依赖**，或者**不应该同时在同一个 goroutine 中被长时间打开**，因为 `读写事务` 需要周期性地 `re-map` 数据，但是当 `只读事务` 打开时，这个操作会造成死锁。

### 4. bolt 的读与写

首先，不管是读还是写，都需要先指定一个 `bucket`，这个概念类似于关系型数据库中的 `table`。对于 `bucket` 的操作，有以下几种：

1.  `CreateBucket` 创建一个 `bucket` ，但当 `bucket` 已经存在时，会返回错误 `bucket already exists`；如果成功，会返回一个 `Bucket`对象：

```go
bucketName := "my-bucket"
_ = db.Update(func(tx *bolt.Tx) error {
    // 通过此方式创建一个 bucket，当 bucket 已经存在时，会返回错误
    b, err := tx.CreateBucket([]byte(bucketName))
    if err != nil {
        return err
    }
    // ... do some thing

    return nil
})


```

2.  `CreateBucketIfNotExists` 创建一个 `bucket`，**创建成功** 或 **`bucket`已经存在**时，返回 `Bucket` 对象：

```go
_ = db.Update(func(tx *bolt.Tx) error {
    // 通过此方式创建一个 bucket，不过 bucket 已经存在时不会返回错误
    b, err := tx.CreateBucketIfNotExists([]byte(bucketName))
    if err != nil {
        return err
    }
    // ...
    return nil
})
```

3.  `Bucket` 选择一个已经存在的 `bucket`，`bucket` 不存在时不会报错，但返回的 `Bucket` 对象为 `nil`，后续所有对 b 的操作都会造成空指针错误：

```go
_ = db.Update(func(tx *bolt.Tx) error {
    // 通过此方式选择一个已经存在的 bucket
    b, err := tx.Bucket([]byte(bucketName))
    if err != nil {
        return err
    }
    fmt.Println(b == nil)  // 如果 bucket 不存在，则 b 为 nil，后面所有对 b 的操作都会造成空指针错误
    return nil
})
```

4.  `DeleteBucket` 删除一个已经存在的 `bucket`，如果 `bucket` 不存在会返回 `bucket not found` 错误。

```go
_ = db.Update(func(tx *bolt.Tx) error {
    // 通过此方式删除一个已经存在的 bucket，如果 bucket 不存在会返回 `bucket not found` 错误
    err := tx.DeleteBucket([]byte(bucketName))
    if err != nil {
        return err
    }
    return nil
})
```

#### 4.1 写 或 修改

只有一种方式：使用 `Put(k,v []byte)` 方法。

```go
_ = db.Update(func (tx *bolt.Tx) error {
    b, err := tx.CreateBucketIfNotExists([]byte(bucketName))
    if err != nil {
        return err
    }
	
    // set name = Jemmy
    err = b.Put([]byte("name"),[]byte("Jemmy"))
    if err != nil {
        return err
    }
})
```

`Value` 不一定是一个字符串，你可以存储整个序列化后的对象：

```go
func main() {
	db, err := bolt.Open("./data.db", os.ModePerm, nil)
	if err != nil {
		panic(err)
	}

	type User struct {
		ID   uint64
		Name string
		Age  int
	}

	bucketName := "my-bucket111"
	err = db.Update(func(tx *bolt.Tx) error {
		// 通过此方式创建一个 bucket，不过 bucket 已经存在时不会返回错误
		b, err := tx.CreateBucketIfNotExists([]byte(bucketName))
		if err != nil {
			return err
		}

		u := &User{
			ID:   1,
			Name: "Jemmy",
			Age:  18,
		}
		data, err := json.Marshal(u)
		if err != nil {
			return err
		}
		key := fmt.Sprintf("%d", u.ID)
		err = b.Put([]byte(key), data)
		if err != nil {
			return err
		}

		fmt.Printf("%s\n", b.Get([]byte(key)))

		return nil
	})
	if err != nil {
		log.Fatal(err)
	}
}
```

输出：

```bash
{"ID":1,"Name":"Jemmy","Age":18}
```

比较有用的一个技巧：可以使用  `NextSequence()` 得到一个递增的 `unique identifier`，你可以把它理解成 `MySQL` 中的递增主键：

```go
func main() {
    db, err := bolt.Open("./data.db", os.ModePerm, nil)
    if err != nil {
        panic(err)
    }

    type User struct {
        ID   uint64
        Name string
        Age  int
    }

    bucketName := "my-bucket222"
    err = db.Update(func(tx *bolt.Tx) error {
        b, err := tx.CreateBucketIfNotExists([]byte(bucketName))
        if err != nil {
            return err
        }
        for i:=0;i<5;i++ {
            u := &User{
                Name: "Jemmy",
                Age:  18,
            }
            // 获取一个主键值。只有当 Tx被关闭 或者 b不可写 时，才会返回错误。在 Update() 函数中不可能发生
            id, err := b.NextSequence()
            if err != nil {
                return err
            }
            u.ID = id
            // 将 user 序列化成 []byte
            data, err := json.Marshal(u)
            if err != nil {
                return err
            }
            key := fmt.Sprintf("%d", u.ID)
            // 使用 Put 保存
            err = b.Put([]byte(key), data)
            if err != nil {
                return err
            }
        }
        
        return nil
    })
    if err != nil {
        log.Fatal(err)
    }

    _ = db.View(func(tx *bolt.Tx) error {
        b := tx.Bucket([]byte(bucketName))

        c := b.Cursor()
        for k, v := c.First(); k != nil; k, v = c.Next() {
            fmt.Printf("key=%s, value=%s\n", k, v)
        }
        return nil
    })
}
```

输出：

```bash
key=1, value={"ID":1,"Name":"Jemmy","Age":18}
key=2, value={"ID":2,"Name":"Jemmy","Age":18}
key=3, value={"ID":3,"Name":"Jemmy","Age":18}
key=4, value={"ID":4,"Name":"Jemmy","Age":18}
key=5, value={"ID":5,"Name":"Jemmy","Age":18}
```

#### 4.2 读取

正如上面代码所示，你可以使用 `func (b *Bucket) Get(key []byte) []byte` 。下面介绍一些更高阶的用法：

1.  遍历整个 `bucket`:

`bolt` 通过 `byte-sorted ` 的顺序在 `bucket` 中存储键值对，这个设计使得对 `key` 的迭代遍历非常方便也非常快：

```go
_ = db.View(func(tx *bolt.Tx) error {
    b := tx.Bucket([]byte(bucketName))

    c := b.Cursor()
    for k, v := c.First(); k != nil; k, v = c.Next() {
        fmt.Printf("key=%s, value=%s\n", k, v)
    }
    return nil
})

// 输出
key=1, value={"ID":1,"Name":"Jemmy","Age":18}
key=2, value={"ID":2,"Name":"Jemmy","Age":18}
key=3, value={"ID":3,"Name":"Jemmy","Age":18}
key=4, value={"ID":4,"Name":"Jemmy","Age":18}
key=5, value={"ID":5,"Name":"Jemmy","Age":18}
```

使用 **游标 cursor** 可以非常方便地移动，类似的函数还有：

```go
First()  Move to the first key.
Last()   Move to the last key.
Seek()   Move to a specific key.
Next()   Move to the next key.
Prev()   Move to the previous key.
```

所以你可以使用下面的方式进行倒序遍历：

```go
_ = db.View(func(tx *bolt.Tx) error {
    b := tx.Bucket([]byte(bucketName))

    c := b.Cursor()
    for k, v := c.Last(); k != nil; k, v = c.Prev() {
        fmt.Printf("key=%s, value=%s\n", k, v)
    }
    return nil
})

// 输出
key=5, value={"ID":5,"Name":"Jemmy","Age":18}
key=4, value={"ID":4,"Name":"Jemmy","Age":18}
key=3, value={"ID":3,"Name":"Jemmy","Age":18}
key=2, value={"ID":2,"Name":"Jemmy","Age":18}
key=1, value={"ID":1,"Name":"Jemmy","Age":18}
```

当然，如果你明确知道你要遍历整个 `bucket`，并且是正序输出，也可以通过 `ForEach`：

```go
_ = db.View(func(tx *bolt.Tx) error {
    b := tx.Bucket([]byte(bucketName))
    err := b.ForEach(func(k, v []byte) error {
        fmt.Printf("key=%s, value=%s\n", k, v)
        return nil
    })
    if err != nil {
        return err
    }
    return nil
})

// 输出
key=1, value={"ID":1,"Name":"Jemmy","Age":18}
key=2, value={"ID":2,"Name":"Jemmy","Age":18}
key=3, value={"ID":3,"Name":"Jemmy","Age":18}
key=4, value={"ID":4,"Name":"Jemmy","Age":18}
key=5, value={"ID":5,"Name":"Jemmy","Age":18}
```

2.  前缀匹配搜索，可以使用 `Seek()` 函数：

```go
_ = db.View(func(tx *bolt.Tx) error {
    // Assume bucket exists and has keys
    c := tx.Bucket([]byte(bucketName)).Cursor()

    prefix := []byte("1")
    for k, v := c.Seek(prefix); k != nil && bytes.HasPrefix(k, prefix); k, v = c.Next() {
        fmt.Printf("key=%s, value=%s\n", k, v)
    }

    return nil
})

// 输出
key=1, value={"ID":1,"Name":"Jemmy","Age":18}
```

3.  范围搜索，也可以使用 `Seek()` 函数：

```go
_ = db.View(func(tx *bolt.Tx) error {
    // Assume bucket exists and has keys
    c := tx.Bucket([]byte(bucketName)).Cursor()

    min := []byte("1")
    max := []byte("3")
    for k, v := c.Seek(min); k != nil && bytes.Compare(k, max) <= 0; k, v = c.Next() {
        fmt.Printf("key=%s, value=%s\n", k, v)
    }

    return nil
})

// 输出
key=1, value={"ID":1,"Name":"Jemmy","Age":18}
key=2, value={"ID":2,"Name":"Jemmy","Age":18}
key=3, value={"ID":3,"Name":"Jemmy","Age":18}
```







