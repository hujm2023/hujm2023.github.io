---
title: "MySQL中InnoDB底层存储原理"
date: 2021-05-05T16:53:51+08:00
draft: true
author: JemmyHu(hujm20151021@gmail.com)
toc: true
mathjax: true
categories: [技术博客, 技术细节, MySQL]
tags: [MySQL, InnoDB, 底层存储原理]
comment: true
cover:
  image: https://pic.downk.cc/item/5f73fbb3160a154a67b4ff7e.jpg
summary:
---

## 一、简述

下图大致描述了 `InnoDB` 的存储结构：

![InnoDB 底层存储结构](https://image.hujm.net/blog/images/20210829175155.png)

从上图来看，所有的数据都被逻辑地存放到 **表空间(Tablespace)** 中，表空间由 `Segment(段)`、`Block(块)` 和 `Page(页)` 等组成。

> 本文重点在于 `Page`。

### 1. Tablespace 表空间

`InnoDB` 的 `表空间(TableSpace)` 可以看做是一个 **逻辑概念**，本质上是一个或多个磁盘文件组成的虚拟文件系统，它不仅存储了表数据和索引数据，还保存了 `undo log`、`insert buffer` 等其他数据结构。

默认情况下， `InnoDB` 有一个 **共享表空间**，即所有的数据都存储在这个共享表空间内。如果配置了 `innodb_file_per_table=On`，则每张表的数据就会单独存放到各自的表空间中，即一个表空间对应磁盘上的一个物理文件，存储在 `innodb_data_home_dir` 下。

需要注意的是，每张表的表空间中存储的只是数据、索引、插入缓冲等内容，其他数据如 `undo log`、系统事务信息等都还是存放在原来的共享表空间中。这也说明，即使设置 `innodb_file_per_table=On`，共享表空间还是会不断增大。

### 2. Segment 段

表空间的下一级称为 `Segment(段)`，表空间由很多 `Segment` 组成，常见的段由 **数据段**、**索引段** 和 **回滚段**等。`Segment` 与数据库中的 **索引**相相映射，创建索引很关键的一步便是分配 `Segment`。在 `InnoDB` 中，每个索引对应两个 `Segment`：管理叶子结点的 `Segment`(`B+树` 的 叶子结点，即数据段，`Leaf node segment`) 和 管理非叶子结点的 `Segment`(`B+树` 的非叶子结点，即索引段，`Non-leaf node segment`)。

### 3. Extent 区
