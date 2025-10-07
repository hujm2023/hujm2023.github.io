---
title: LeetCode-两数之和问题
author: JemmyHu(hujm20151021@gmail.com)
toc: true
mathjax: true
summary:
categories: [技术博客, 算法题解, 数组]
tags: [LeetCode, 数组, 两数之和]
comment: true
date: 2020-09-19 13:22:24
cover:
  image: https://pic.downk.cc/item/5f65a612160a154a6789ec2f.jpg
---

`leetcode` 上 `twoSum` 相关的问题：

- [1. 两数之和](https://leetcode-cn.com/problems/two-sum/)
- [167. 两数之和 II - 输入有序数组](https://leetcode-cn.com/problems/two-sum-ii-input-array-is-sorted/)
- [170. 两数之和 III .数据结构设计](https://leetcode-cn.com/problems/two-sum-iii-data-structure-design/)

## 1. 问题描述

> 给定一个整数数组 nums 和一个目标值 target，请你在该数组中找出和为目标值的那 两个 整数，并返回他们的数组下标。
>
> 你可以假设每种输入只会对应一个答案。但是，数组中同一个元素不能使用两遍。
>
> 示例:
>
> ```bash
> 给定 nums = [2, 7, 11, 15], target = 9
>
> 因为 nums[0] + nums[1] = 2 + 7 = 9
> 所以返回 [0, 1]
> ```

## 2. 解决思路

一般情况下，使用的是暴力穷举法，但是这种情况下时间复杂度为 $O(n^2)$，爆炸，不考虑。

这里采用 **空间换时间** 的思路：

> 设置一个 `map[int]int` ，其中 `key` 存储数组中的元素，`value` 为数组中元素的索引值。之后遍历数组，设`i,j` 为当前索引和元素，如果 `target-j`在 `map` 中，则当前的 索引`i`和 `map[target-j]` 即为所需要的。

下面通过代码实现：

```go
func twoSum(nums []int, target int) []int {
    result := make([]int,0)
    m := make(map[int],int)
    for i,j := range nums {
        if v, ok := m[target-j]; ok {
            result = append(result, v)
            result = append(result, i)
        }
        m[j] = i
    }
 return result
}
```

## 3. 进阶

设计并实现一个 `TwoSum` 的类，使该类需要支持 `add` 和 `find` 的操作。

`add` 操作 - 对内部数据结构增加一个数。
`find` 操作 - 寻找内部数据结构中是否存在一对整数，使得两数之和与给定的数相等。

示例 1:

```bash
add(1); add(3); add(5);
find(4) -> true
find(7) -> false
```

示例 2:

```bash
add(3); add(1); add(2);
find(3) -> true
find(6) -> false
```

实现如下：

```go
type TwoSum struct {
    M map[int]int
}

/** Initialize your data structure here. */
func Constructor() TwoSum {
    return TwoSum{M: make(map[int]int)}
}

/** Add the number to an internal data structure.. */
func (this *TwoSum) Add(number int) {
    this.M[number]++  // 这里的map中，key保存number，value保存出现的次数
}

/** Find if there exists any pair of numbers which sum is equal to the value. */
func (this *TwoSum) Find(value int) bool {
    for key := range this.M {
        other := value - key
        // 第一种情况，针对出现了两次的元素、value为其2倍的，比如 [3,3]，value为6
        if other == key && this.M[other] > 1 {
            return true
        }
        // 第二种情况，针对出现过一次的元素，比如 [2,6], value 为8
        if other != key && this.M[other] > 0 {
            return true
        }
    }
    return false
}
```

## 4. 总结

**对于题目 1 和题目 167：** 设置一个 `map[int]int` ，其中 `key` 存储数组中的元素，`value` 为数组中元素的索引值。之后遍历数组，设`i,j` 为当前索引和元素，如果 `target-j`在 `map` 中，则当前的索引`i`和 `map[target-j]` 即为所需。

**对于题目 170：** 设计数据结构时，`map` 的 `key` 为元素，`value` 为该元素出现的此时。查找时，考虑两种情况：一种是 `[3,3]-->6` 的情况，一种是 `[2,5] --> 7` 的情况。
