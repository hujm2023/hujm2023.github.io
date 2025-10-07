---
title: "Git 详解"
date: 2020-11-05T11:01:28+08:00
draft: true
categories: [技术博客, 技术细节, Git]
tags: [Git]
---

## 一、Git 底层存储原理

`Git` 是一个 **内容寻址文件系统**。其底层存储从本质上讲是一个基于文件系统实现的 `Key-Value` 数据库，这里的 `Value` 是指 `git` 中三种不同的对象，而 `Key` 是该对象对应的哈希值。你可以向 `git` 仓库中插入任何类型的文件，它会返回给你一个唯一的键，通过该键你可以在任何时刻再次取回该文件。其中 `Key` 会被存储为目录加文件名(`hash` 值前两位作为目录名，剩下部分作为文件名，这样做的目的是为了 **加快文件的定位**， 在查找文件时先找到对应的目录,，再遍历目录中的文件进行查找)，`Value` 则被存储为文件内容，默认使用 `zlib` 压缩。

接下来我们详细了解一下 `git` 的四种不同对象：`blob` 、 `tree` 、 `commit` 和 `tag` 对象。

`Git` 以一种类似于 `UNIX` 文件系统的方式存储内容，但作了些许简化。 所有内容均以`tree 对象` 和 `blob对象` 的形式存储，其中 `tree 对象` 对应了 `UNIX` 中的 **目录项**，数据对象则大致上对应了 **文件**。

首先，使用 `git init learn_git` 创建一个项目，我们后面的操作都会在这个目录中。

```bash
$ git init learn_git
Initialized empty Git repository in /Users/hujiaming/Downloads/learn_git/.git/
```

在学习之前，我们先看两条 `git` 底层的命令：

- **`git hash-object`：向 `Git` 数据库中写入数据**

先看操作：

```bash
$ echo 'test content' | git hash-object --stdin -w
d670460b4b4aece5915caf5c68d12f560a9fe3e4
```

> `git hash-object` 会接受你传给它的东西，而它只会返回可以存储在  `Git` 仓库中的唯一键。 `-w` 选项会指示该命令不要只返回键，还要将该对象写入数据库中。 最后，`--stdin` 选项则指示该命令从标准输入读取内容；若不指定此选项，则须在命令尾部给出待存储文件的路径。

此时，会在 `.git/objects/` 目录下生成对应的 `Key(目录+文件)`：

```bash
$ tree -a
.
└── .git
    ├── objects
    │   ├── d6
    │   │   └── 70460b4b4aece5915caf5c68d12f560a9fe3e4
    ...
```

> 对内容 `test content` 生成的唯一哈希为 `d670460b4b4aece5915caf5c68d12f560a9fe3e4`，存储时，取前两位 `d6` 作为文件夹名，剩余位表示文件名。

- **`git cat-file`：查看 `Git` 数据库中的内容(或类型)**

一旦你将内容存储在了对象数据库中，那么可以通过 `cat-file` 命令从 `Git` 那里取回数据。

```bash
$ git cat-file -p d670460b4b4aece5915caf5c68d12f560a9fe3e4 
test content
$ git cat-file -t d670460b4b4aece5915caf5c68d12f560a9fe3e4 
blob
```

> `-t` 选项用于查看键值对应数据的类型，`-p` 选项用于查看键值对应的数据内容。
>
> 这里的 `blob` 即是 `git` 的基础对象之一，后面会详细介绍。

这两个命令正好对应键值对系统最常见的两个操作：`Set` 和 `Get`。接下来我们详细了解。

### 1. 四种 `git` 对象

#### 1.1 `blob` 对象

`blob` 对象只跟文本文件的内容有关，就是一块二进制数据，和文本文件的名称及目录无关，只要是相同的文本文件，会指向同一个 `blob`。

你可以把一个 `blob` 对象理解成这样的一个结构：

```go
type blob = []byte
```

如果我们确定一个对象是 `blob` 对象，可以使用 `git show <hash>` 命令来查看其对应的内容：

```bash
$ git show git show 9daeafb9864cf43055ae93beb0afd6c7d144bfa4
test
```

#### 1.2 `tree` 对象

`tree` 对象记录文本文件内容和名称、目录等信息，每次提交都会生成一个顶层 `tree` 对象，它可以指向其引用的 `tree` 或 `blob`。

它有好多个指向 `blob` 对象或是其它 `tree` 对象的指针，它一般用来表示内容之间的目录层次关系。

你可以把一个 `tree` 对象理解成这样的结构：

```go
type tree = map[string]<tree | blob>
```

假设经过一系列的操作，我们的目录目前是这样的：

```bash
.
└── test_folder
    ├── 1.txt
    ├── 2.txt
    ├── demo.txt
    └── folder
        ├── 3.txt
        └── 4.txt
```

这些文件中的内容如下：

```bash
$ cat 1.txt 2.txt demo.txt
1
2
test

$ cd folder && cat 3.txt 4.txt
3
4
```

提交之后，看下 `objects` 目录下是什么样：

```bash
$ find .git/objects -type f 
.git/objects/0c/fbf08886fca9a91cb753ec8734c84fcbe52c9f
.git/objects/9d/aeafb9864cf43055ae93beb0afd6c7d144bfa4
.git/objects/9d/a9490e6d5a61fa25777baffb02e02152f158ac
.git/objects/d0/0491fd7e5bb6fa28c517a0bb32b8b506539d4d
.git/objects/d6/70460b4b4aece5915caf5c68d12f560a9fe3e4
.git/objects/27/2db0863401c3077815f256051ea1d80b942a9e
.git/objects/81/3f4c65403ed4403ef06727b3a38dbc29dc7f24
.git/objects/00/750edc07d6415dcc07ae0351e9397b0222b7ba
.git/objects/65/6cc49515b310cb2f5e7c47547e80a8e68f9450
.git/objects/97/db59dcab8e7ae801dc1f75fc62b4e20bd2b81b
.git/objects/b8/626c4cff2849624fb67f87cd0ad72b163671ad
.git/objects/dc/83e00cee1d37faec20fca7f5213697620e78e5
.git/objects/cb/e260de3bfbb344ba0f02ebbc21bf2f4c53f81f
```

我们选择其中一个特殊的：

```bash
$ git cat-file -p 813f4c65403ed4403ef06727b3a38dbc29dc7f24 
100644 blob d00491fd7e5bb6fa28c517a0bb32b8b506539d4d 1.txt
100644 blob 0cfbf08886fca9a91cb753ec8734c84fcbe52c9f 2.txt
100644 blob 9daeafb9864cf43055ae93beb0afd6c7d144bfa4 demo.txt
040000 tree 272db0863401c3077815f256051ea1d80b942a9e folder

# 同样，你也可以使用 git ls-tree 来查看一个 tree 对象的内容，如下：
$ git ls-tree 272db0863401c3077815f256051ea1d80b942a9e 
100644 blob 00750edc07d6415dcc07ae0351e9397b0222b7ba 3.txt
100644 blob b8626c4cff2849624fb67f87cd0ad72b163671ad 4.txt
```

这个结构我们可以这样表示：![test_folder tree 对象](https://tva1.sinaimg.cn/large/0081Kckwgy1gjzdog0dhfj31or0u04bn.jpg)

一个 `tree` 对象可以指向  一个包含文件内容的 `blob` 对象,，也可以是其它包含某个子目录内容的其它 `tree` 对象。`tree` 对象和 `blob` 对象一样，都用其内容的 `SHA1` 哈希值来命名，只有当两个 `tree` 对象的内容完全相同(包括其所指向所有子对象)时，它的名字(哈希值)才会一样(文件系统底层是 [默克尔树](https://jemmyh.github.io/2020/10/22/you-xiu-shu-ju-jie-gou-mo-ke-er-shu/))，反之亦然。这样就能让 `git` 仅仅通过比较两个相关的 `tree` 对象的名字是否相同，来快速的判断其内容是否不同。

#### 1.3 `commit` 对象

`commit` 对象记录本次提交的所有信息，包括提交人、提交时间、本次提交包含的 `tree` 及 `blob`。或者说，一个 `commit` 对象保存了一次 `commit` 的信息，包括作者，提交注释，并且指向父 `commit` 对象和一个 `tree` 对象。这个 `tree` 对象是当前项目快照。

还是以上面的目录为例，我进行了两次提交：

```bash
$ git log

commit 656cc49515b310cb2f5e7c47547e80a8e68f9450 (HEAD -> master)
Author: Jemmy <hujm20151021@gmail.com>
Date:   Thu Oct 22 20:50:37 2020 +0800

    test tree

commit 97db59dcab8e7ae801dc1f75fc62b4e20bd2b81b
Author: Jemmy <hujm20151021@gmail.com>
Date:   Thu Oct 22 20:34:13 2020 +0800

    init
```

我们来看一下这两次提交的内容：

```bash
git cat-file -p 656cc49515b310cb2f5e7c47547e80a8e68f9450
tree 9da9490e6d5a61fa25777baffb02e02152f158ac
parent 97db59dcab8e7ae801dc1f75fc62b4e20bd2b81b
author Jemmy <hujm20151021@gmail.com> 1603371037 +0800
committer Jemmy <hujm20151021@gmail.com> 1603371037 +0800

test tree

$ git cat-file -p 97db59dcab8e7ae801dc1f75fc62b4e20bd2b81b
tree dc83e00cee1d37faec20fca7f5213697620e78e5
author Jemmy <hujm20151021@gmail.com> 1603370053 +0800
committer Jemmy <hujm20151021@gmail.com> 1603370053 +0800

init
```

你可以把一个 `commit 对象` 理解成如下的结构：

```go
type commit = struct {
    parent: []*commit
    author: string
    message: string
    snapshot: tree
}
```

我们画出这两次提交对应的 `tree` 、`parent` 等对应关系：

![前两次提交](https://tva1.sinaimg.cn/large/0081Kckwgy1gjzgzaoqv0j31wb0u0x6b.jpg)

此时我们再进行一次提交，但是只修改其中的一个文件：

```bash
$ echo "new version 1" >> 1.txt
$ cat 1.txt
1
new version 1

$ git add .
$ git commit -m "update 1.txt"
```

此时查看 `git log`：

```bash
commit eaa9bdcee43796e3e880138103f57985c1004deb (HEAD -> master)
Author: Jemmy <hujm20151021@gmail.com>
Date:   Fri Oct 23 17:52:41 2020 +0800

    update 1.txt

commit 656cc49515b310cb2f5e7c47547e80a8e68f9450
Author: Jemmy <hujm20151021@gmail.com>
Date:   Thu Oct 22 20:50:37 2020 +0800

    test tree

commit 97db59dcab8e7ae801dc1f75fc62b4e20bd2b81b
Author: Jemmy <hujm20151021@gmail.com>
Date:   Thu Oct 22 20:34:13 2020 +0800

    init
```

我们依旧画出他们之间的对应关系：

![第三次提交](https://tva1.sinaimg.cn/large/0081Kckwgy1gjzh0xo9k8j31d50u0e81.jpg)

一条提交记录包含 **表示当前提交的 `hash` 值**、**作者**、**提交日期**、**提交的备注(提交者自行填写)**。每一次 `commit` 都会生成一个 `commit 对象`，同时将被修改的文件新建一个 `blob` 对象，然后更新暂存区，更新 `tree` 对象(如果某个对象发生了改变，则新建一个对象，然后从这个对象所在的层，根据最小变动原则去重建默克尔树)，最后创建一个指明了顶层树表示新的提交。

再看第二次提交与第三次提交之间的变化，我们只改变了 `test_folder` 下的 `1.txt`，那么 `test_folder` 这个默克尔树的树根的哈希值肯定会发生变化，而其他的文件和子文件夹都未发生变化。同样，我进行了第四次提交，只不过这次改了子文件夹 `folder` 下的 `4.txt`，那么你也应该能明白此刻树的对应关系：

![第四次提交](https://tva1.sinaimg.cn/large/0081Kckwgy1gjzmw2hvoyj311f0u01ky.jpg)

#### 1.4 `tag` 对象

标签就是一次提交的快照。通常它保存的是需要追溯的特定版本数据的一个 `commit` 对象的数字签名。

我们对第四次提交打一个 `tag`：

```bash
git tag -a v1.0.0 -m "version 1.0.0"
```

在 `.git` 目录下，我们也能看到这样的一个文件：

```bash
$ find .git/refs -type f
.git/refs/tags/v1.0.0
```

我们直接查看这个 `tag` 的内容：

```bash
$ git cat-file -p v1.0.0
object b9adced0295bc8a4b073eb03f26f5df9b17b316f
type commit
tag v1.0.0
tagger Jemmy <hujm20151021@gmail.com> 1603525467 +0800

version 1.0.0
```

这个 `object` 对应的哈希值，正是我们第四次 `commit` 所对应的 `commit` 对象的哈希值。

### 2. `pack` 机制

我们先看一个场景。首先，我们新建一个文件，然后提交：

```bash
echo "t1" > myfile.txt
git add .
git commit -m "new myfile"
```

此时查看 `./git/objects` 目录下的内容，会发现生成了一个 `blob` 对象：

```bash
$ find .git/objects -type f
...
.git/objects/79/5ea43143ebd1173b2ff6d1f24e7705306545dd
...
```

查看内容，确实是我们刚刚写入的内容：

```bash
$ git cat-file -p 795ea4
t1
```

然后，我们更新 `myfile.txt`，再提交：

```bash
echo "t2" >> myfile.txt
git add .
git commit -m "update myfile"
```

再去查看 `.git/objects` 下的内容，会发现有两个版本：

```bash
$ find .git/objects -type f
...
.git/objects/79/5ea43143ebd1173b2ff6d1f24e7705306545dd
.git/objects/ba/2189284327ba4b6254880b19a1644f083f3f52
...

$ git cat-file -p 795ea4
t1

$ git cat-file -p ba2189
t1
t2
```

这种存储模式被称为 **松散的存储模式**，即一个文件的不同版本，都是全量保存其全部数据。文件较小时还好，但遇到几十 K 甚至几十 M 的较大文件时，会很难受。如果 `git` 只完整保存最初的一个版本，再保存后来版本与之前版本的差异，岂不是更好？

事实上 `git` 确实这么做了。在进行一些特定操作(如`git pull` 或 `git push`)时，`git` 会将这些文件 **打包(`pack`)** 成一个被称为 **包文件(`packfile`)** 的二进制文件，目的是节省存储空间和提高传输效率。当然我们可以手动执行这个 **打包** 操作：`git gc` 命令。我们执行以下看下效果：

```bash
$ git gc 
Enumerating objects: 28, done.
Counting objects: 100% (28/28), done.
Delta compression using up to 8 threads
Compressing objects: 100% (13/13), done.
Writing objects: 100% (28/28), done.
Total 28 (delta 1), reused 21 (delta 1)
Computing commit graph generation numbers: 100% (6/6), done.
```

我们再查看 `.git/objects` 目录：

```bash
find .git/objects -type f 
.git/objects/d6/70460b4b4aece5915caf5c68d12f560a9fe3e4
.git/objects/pack/pack-d6aa12c9eb0ba2146436a0f35d583f114cae395e.pack
.git/objects/pack/pack-d6aa12c9eb0ba2146436a0f35d583f114cae395e.idx
.git/objects/info/commit-graph
.git/objects/info/packs
```

我们发现大部分文件都不见了，取而代之的是一些 `pack` 目录下的两个文件——包文件 和 索引。包文件包含了刚才从文件系统中移除的所有对象的内容，索引文件包含了包文件的偏移信息(`deltas`)，我们通过索引文件就可以快速定位任意一个指定对象。

> 仍然还有 `d67046` 文件，是因为这是我们刚开始执行 `echo 'test content' | git hash-object --stdin -w` 结果。因为它不属于任何提交记录，所以 `git` 认为它是 **悬空(`dangling`)** 的，不会将它打包进新生成的包文件中。

我们使用 `git verify-pack -v` 这个命令来查看已打包的内容：

```bash
$ git verify-pack -v .git/objects/pack/pack-d6aa12c9eb0ba2146436a0f35d583f114cae395e.idx

6d8b3c6beb1011636620357b045d2512cf240e37 commit 222 155 12
bb422cd714c2d90ff6db2be782539d9f4d8d6b78 commit 219 152 167
b9adced0295bc8a4b073eb03f26f5df9b17b316f commit 221 153 319
6ba319b1e58399e57ed713b29e3a68d1ba1a80a7 tag    141 132 472
eaa9bdcee43796e3e880138103f57985c1004deb commit 221 154 604
  1 t1
656cc49515b310cb2f5e7c47547e80a8e68f9450 commit 218 151 758
97db59dcab8e7ae801dc1f75fc62b4e20bd2b81b commit 165 116 909
4ac653aa476d9f432507111fccfbad6553292d55 tree   76 85 1025
fb32c7db86622ace20051e6472179c8ced27854f tree   135 134 1110
ac3f5fd7d29dc89e4ed56e4c520602c353e7a6f8 tree   66 71 1244
2e3c781f2d9f2c3af49c282a3d96036a581cfe3c tree   76 86 1315
6489f94de913c52c6b105b3b6085f469a5514d83 tree   38 47 1401
ac683f18f67686e098e0fe1056b23ddaa2e92d27 tree   38 47 1448
272db0863401c3077815f256051ea1d80b942a9e tree   66 70 1495
9da9490e6d5a61fa25777baffb02e02152f158ac tree   38 47 1565
813f4c65403ed4403ef06727b3a38dbc29dc7f24 tree   135 134 1612
dc83e00cee1d37faec20fca7f5213697620e78e5 tree   38 47 1746
cbe260de3bfbb344ba0f02ebbc21bf2f4c53f81f tree   36 49 1793
ba2189284327ba4b6254880b19a1644f083f3f52 blob   6 15 1842
43b21c7cff298ccaa84205c3a8233456e31eae42 blob   16 26 1857
0cfbf08886fca9a91cb753ec8734c84fcbe52c9f blob   2 11 1883
9daeafb9864cf43055ae93beb0afd6c7d144bfa4 blob   5 14 1894
00750edc07d6415dcc07ae0351e9397b0222b7ba blob   2 11 1908
06de34b01434869f9ebd794ce71988a33c79079b blob   16 26 1919
795ea43143ebd1173b2ff6d1f24e7705306545dd blob   3 12 1945
9f66ab0ee464471df883e07673a39bbe1adb024c tree   27 40 1957 1 fb32c7db86622ace20051e6472179c8ced27854f
b8626c4cff2849624fb67f87cd0ad72b163671ad blob   2 11 1997
d00491fd7e5bb6fa28c517a0bb32b8b506539d4d blob   2 11 2008
non delta: 27 objects
chain length = 1: 1 object
.git/objects/pack/pack-d6aa12c9eb0ba2146436a0f35d583f114cae395e.pack: ok
```

第 3 列表示对象的大小，同时还观察到 `9f66ab` 这个对象引用了 `fb32c7` 对象，借助 `1.3` 中最后一张图，以及对应的内容，我们发现，这两棵树内容的唯一区别就在于 `./test_folder/folder/4.txt`，前者存的是旧版本，后者存的是新版本，即后者是前者的第二个版本。需要注意的是，第二个版本完整地保存了文件的内容，而原始版本反而是以差异的方式保存的，**这是因为大部分情况下需要快速访问文件的最新版本**。

### 3. 引用

先看一下我们目前的进展：

```bash
$ git log --pretty=oneline
21cc60f134b4d1cf898905790ad12e51ec8c6a17 (HEAD -> master) update 1.txt version 2
4741fa26a05b943f1d7068ae8c6909fdc6ca908a update myfile t4
629be158cf9db84a8857559406e30e0c924e86b5 update myfile t3
6d8b3c6beb1011636620357b045d2512cf240e37 update myfile
bb422cd714c2d90ff6db2be782539d9f4d8d6b78 new myfile
b9adced0295bc8a4b073eb03f26f5df9b17b316f (tag: v1.0.0) update 4.txt
eaa9bdcee43796e3e880138103f57985c1004deb update 1.txt
656cc49515b310cb2f5e7c47547e80a8e68f9450 test tree
97db59dcab8e7ae801dc1f75fc62b4e20bd2b81b init
```

想要记住每一次提交的哈希值似乎不太可能，所以才会出现 `git引用`——**`git`引用相当于给 40 位 `hash` 值取一个别名，便于识别和读取**。`git 引用` 对象存储在 `.git/refs` 目录下，该目录下有3个子文件夹 `heads`、`tags` 和 `remotes`，分别对应于 `HEAD引用`、`标签引用` 和 `远程引用`。

#### 3.1 `HEAD引用`

先说结论，`HEAD引用` 有两种：一种是分支级别的，存储在 `.git/refs/heads/` 目录下，用来记录分支的最后一次提交，使用 `git update-ref` 来维护；另一种是代码库级别的，存储在 `.git/HEAD` 中，用来记录代码库当前所在的分支，使用 `git symbolic-ref` 来维护。

我们先来看分支级别的。此时 `HEAD引用` 用来指向每个分支的最后一次提交的对象，这样的目的是，每一次切换分支后，就能知道分支的“尾巴”在哪里。当然我们可以手动去更新某个分支的“尾巴”。

还是打印出我们的 `log` 以及 `status`：

```bash
$ git log --pretty=oneline
2f42ff5d10653abb49c97a316ec50bef69897048 (HEAD -> dev, master) add dev file
21cc60f134b4d1cf898905790ad12e51ec8c6a17 update 1.txt version 2
4741fa26a05b943f1d7068ae8c6909fdc6ca908a update myfile t4
629be158cf9db84a8857559406e30e0c924e86b5 update myfile t3
6d8b3c6beb1011636620357b045d2512cf240e37 update myfile
bb422cd714c2d90ff6db2be782539d9f4d8d6b78 new myfile
b9adced0295bc8a4b073eb03f26f5df9b17b316f (tag: v1.0.0) update 4.txt
eaa9bdcee43796e3e880138103f57985c1004deb update 1.txt
656cc49515b310cb2f5e7c47547e80a8e68f9450 test tree
97db59dcab8e7ae801dc1f75fc62b4e20bd2b81b init

$ git status
On branch dev
nothing to commit, working tree clean
```

我们使用下面的命令，将 `HEAD` 指向 `update myfile t4` 这次提交：

```bash
git update-ref refs/heads/dev 4741fa26a05b943f1d7068ae8c6909fdc6ca908a
```

此时再查看 `log` 和 `status`：

```bash
$ git log --pretty=oneline
4741fa26a05b943f1d7068ae8c6909fdc6ca908a (HEAD -> dev) update myfile t4
629be158cf9db84a8857559406e30e0c924e86b5 update myfile t3
6d8b3c6beb1011636620357b045d2512cf240e37 update myfile
bb422cd714c2d90ff6db2be782539d9f4d8d6b78 new myfile
b9adced0295bc8a4b073eb03f26f5df9b17b316f (tag: v1.0.0) update 4.txt
eaa9bdcee43796e3e880138103f57985c1004deb update 1.txt
656cc49515b310cb2f5e7c47547e80a8e68f9450 test tree
97db59dcab8e7ae801dc1f75fc62b4e20bd2b81b init

$ git status
On branch dev
Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
 new file:   dev.txt
 modified:   test_folder/1.txt
```

可以发现，我们**后面的两次提交信息不见了，但是两次提交的修改还在**，不过还未加入到缓冲区。我们执行下面的操作：

```bash
$ git add .
$ git commit -m "test git update-ref"
[dev 52614d4] test git update-ref
 2 files changed, 1 insertion(+)
 create mode 100644 dev.txt
```

此时再去查看 `log`：

```bash
$ git log --pretty=oneline
52614d4c98b9cf787ee0a3adcdf0027f9881c10c (HEAD -> dev) test git update-ref
4741fa26a05b943f1d7068ae8c6909fdc6ca908a update myfile t4
629be158cf9db84a8857559406e30e0c924e86b5 update myfile t3
6d8b3c6beb1011636620357b045d2512cf240e37 update myfile
bb422cd714c2d90ff6db2be782539d9f4d8d6b78 new myfile
b9adced0295bc8a4b073eb03f26f5df9b17b316f (tag: v1.0.0) update 4.txt
eaa9bdcee43796e3e880138103f57985c1004deb update 1.txt
656cc49515b310cb2f5e7c47547e80a8e68f9450 test tree
97db59dcab8e7ae801dc1f75fc62b4e20bd2b81b init
```

会发现生成了新的一个 `commit`，保存了之前的修改，但是后面的提交信息不见了！这在某些场景下非常有用，比如某次提交之后又改了一些东西，但是不想有一次新的提交，这个时候就用的上这个命令了。

再看看代码库级别的 `HEAD引用`。`.git/HEAD` 表名当前处在哪个分支：

```bash
$ cat .git/HEAD
ref: refs/heads/dev
```

没错，当前分支正是 `dev`。我们发现，`.git/HEAD` 中的内容不是 40 位哈希值，而是文本，内容是第一种 `HEAD` 的位置。我们手动去修改一下看看：

```bash
echo "ref: refs/heads/master" > .git/HEAD
```

会发现同步切换到了 `master` 分支！其实有专门的命令来操作 `.git/HEAD` 对象：

```bash
git symbolic-ref HEAD refs/heads/dev
```

会发现又切换回了 `dev` 分支。这就是 `git checkout xxx` 的底层原理。

#### 3.2 标签引用

### 4. `.git` 目录结构

## 二、一些技巧

### 1. 修改已经 `push` 的 `commit` 信息

```bash
# 比如想修改最近三次的
git rebase -i HEAD~3

# 将需要修改的某一次提交前面的 pick 改为 edit；

# 将 commit 信息改成你想改的
git commit —amend 

# 保存
git rebase —continue

# 强制推送到远端(有风险，如果此时别人有一个 commit，将会被你的提交所覆盖)
git push --force
```

## 参考资料

- [视频 这才是真正的 Git](https://www.bilibili.com/video/av77252063)
- [图解Git](https://marklodato.github.io/visual-git-guide/index-zh-cn.html)
- [图解git原理的几个关键概念](https://tonybai.com/2020/04/07/illustrated-tale-of-git-internal-key-concepts/)
- [Git book](https://git-scm.com/book/zh/v2/)
- [Youtube: Git Internals - How Git Works - Fear Not The SHA!](https://www.youtube.com/watch?v=P6jD966jzlk)
- [Youtube: Lecture 6: Version Control (git) (2020)](https://www.youtube.com/watch?v=2sjqTHE0zok)
- [Youtube: 理解 merge 和 rebase](https://www.youtube.com/watch?v=CRlGDDprdOQ)
- [Git 内部原理之 Git 引用](
