---
title: LeetCode-三数之和问题
author: JemmyHu(hujm20151021@gmail.com)
toc: true
mathjax: true
categories: [技术博客, 算法题解, 数组]
tags: [LeetCode, 数组, 三数之和]
comment: true
date: 2020-09-19 18:57:30
cover:
  image: https://pic.downk.cc/item/5f73fc35160a154a67b51b0c.jpg
summary:
---

`leetcode` 上 `三数之和` 问题：

- [15. 三数之和](https://leetcode-cn.com/problems/3sum/)
- [259. 较小的三数之和](https://leetcode-cn.com/problems/3sum-smaller/)
- [16. 最接近的三数之和](https://leetcode-cn.com/problems/3sum-closest/)

## 1. 题目描述

> 给你一个包含 `n` 个整数的数组 `nums`，判断 `nums` 中是否存在三个元素`a，b，c` ，使得 `a + b + c = 0`？请你找出所有满足条件**且不重复**的三元组。
>
> 注意：**答案中不可以包含重复的三元组**。
>
> 示例：
>
> ```bash
> 给定数组 nums = [-1, 0, 1, 2, -1, -4]，
>
> 满足要求的三元组集合为：
> [
>   [-1, 0, 1],
>   [-1, -1, 2]
> ]
> ```

## 2. 解题思路

直接跳过暴力解法，说说此题的思路。

首先，对这个数字排一下序；

之后，采取**固定一个数，同时用双指针来查找另外两个数的方式**求解：

1. 比如，先固定第一个元素，下一个元素设置为 `left` 指针，最后一个元素设置为 `right` 指针；
2. 计算这三个数之和是否为 0，如果是，这就是一组满足条件的三元组；如果不是，看结果与 0 的关系，如果小于 0，则 `left` 向右移动，再比较，如果大于 0，则 `right` 向左移动一位，再比较。
3. 当然，如果当 固定元素+left > 0 或者 固定元素+right < 0 时，就没必要再去比较了。

以下是代码实现：

```go
func threeSum(nums []int) [][]int {
    result := make([][]int, 0)

    sort.Ints(nums) // 先给nums排序

    var pin, left, right int // 固定 左 右指针
    l := len(nums)           // 数组长度

    for i := 0; i < l-2; i++ {
        // 最外层循环为 固定指针

        pin = i
        left = i + 1  // left 为固定指针的下一个元素
        right = l - 1 // right 为最后一个元素

        // 如果最小的大于0，不用再循环了
        if nums[pin] > 0 {
            break
        }

        // 跳过 pin 相同的
        if i > 0 && nums[pin] == nums[pin-1] {
            continue
        }

        for left < right {
            // 找到一个三元组
            if nums[pin]+nums[left]+nums[right] == 0 {
                result = append(result, []int{nums[pin], nums[left], nums[right]})
                // 跳过left相同的
                for left < right && nums[left] == nums[left+1] {
                    left++
                }
                // 跳过 right 相同的
                for left < right && nums[right] == nums[right-1] {
                    right--
                }
                // 找到之后，同时改变
                left++
                right--
            } else if nums[pin]+nums[left]+nums[right] < 0 {
                // 左指针向右移动
                left++
            } else {
                right--
            }

        }

    }
    return result
}
```

## 3. 进阶 1——较小的三数之和

> 给定一个长度为 n 的整数数组和一个目标值 target，寻找能够使条件 nums[i] + nums[j] + nums[k] < target 成立的三元组 i, j, k 个数（0 <= i < j < k < n）。
>
> 示例：
>
> ```bash
> 输入: nums = [-2,0,1,3], target = 2
> 输出: 2
> 解释: 因为一共有两个三元组满足累加和小于 2:
>      [-2,0,1]
>      [-2,0,3]
> ```

直接上代码：

```go
func threeSumSmaller(nums []int, target int) int {
    result := 0     // 满足条件的三元组数目
    sort.Ints(nums) // 先排序

    var pin, left, right int // 固定、左、右 指针
    l := len(nums)           // 数组长度

    for i := 0; i < l-2; i++ {
        pin = i      // 固定指针
        left = i + 1  // 左指针指向固定指针的下一个
        right = l - 1 // 右指针指向最后一个元素

        for left < right {
            if nums[pin]+nums[left]+nums[right] >= target {
            // 说明这个 right 不能出现在三元组中, right 左移一位
            right--
            } else {
                // 从 left 到 right 之间的那几对都符合条件， left 右移一位
                result += right - left
                left++
            }
        }
    }
    return result
}
```

## 4. 进阶 2——最接近的三数之和

> 给定一个包括 n 个整数的数组 nums 和 一个目标值 target。找出 nums 中的三个整数，使得它们的和与 target 最接近。返回这三个数的和。假定每组输入只存在唯一答案。
>
> 示例：
>
> ```bash
> 输入：nums = [-1,2,1,-4], target = 1
> 输出：2
> 解释：与 target 最接近的和是 2 (-1 + 2 + 1 = 2) 。
> ```

代码如下：

```go
func threeSumClosest(nums []int, target int) int {
    result := math.MaxInt32  // 结果
    sort.Ints(nums)          // 先排序
    var pin, left, right int // 固定指针 左指针 右指针
    l := len(nums)           // 数组长度

        // 求绝对值
    abs := func(a int) int {
        if a < 0 {
            return -1 * a
        }
        return a
    }

    // 更新 result
    updateFunc := func(sum int) {
        if abs(sum-target) < abs(result-target) {
            result = sum
        }
    }

    for i := 0; i < l-2; i++ {
        pin = i
        left = i + 1
        right = l - 1

        // 不要重复
        if i > 0 && nums[pin] == nums[pin-1] {
            continue
        }

        for left < right {
        // 如果 right 左移一位，结果离得更远了，说明需要left向右移
        //result = min(result, nums[pin]+nums[left]+nums[right])
            sum := nums[right] + nums[left] + nums[pin]
            if sum == target {
                return target
            }
            updateFunc(sum)
            if sum > target {
                // 此时需要向左移动 right，并且移动到下一个不相等的
                tmp := right - 1
                for left < tmp && nums[tmp] == nums[right] {
                    tmp--
                }
                right = tmp
            } else {
                // 向右移动left
                tmp := left + 1
                for tmp < right && nums[tmp] == nums[left] {
                    tmp++
                }
                left = tmp
            }
        }
    }
    return result
}
```

## 5. 总结

解决此类问题，一般都是 **升序后，外层循环 + 内层双指针** 思路。其中最关键的是 **左右指针移动的条件**，一般都是和 `target` 比大小，大于 `target` 就向左移动右指针，小于 `target` 就向右移动左指针。

由此延伸到 **四数之和** 问题，解决思路与之类似，设置两个固定指针，即外层两个循环，剩下的处理逻辑与 **三数之和** 一样。
看一下 **四数之和**：

> 给定一个包含 n 个整数的数组 nums 和一个目标值 target，判断 nums 中是否存在四个元素 a，b，c 和 d ，使得 a + b + c + d 的值与 target 相等？找出所有满足条件且不重复的四元组。
>
> 注意：
>
> **答案中不可以包含重复的四元组。**
>
> ```bash
> 示例：
>
> 给定数组 nums = [1, 0, -1, 0, -2, 2]，和 target = 0。
>
> 满足要求的四元组集合为：
> [
>   [-1,  0, 0, 1],
>   [-2, -1, 1, 2],
>   [-2,  0, 0, 2]
> ]
> ```

```go
func fourSum(nums []int, target int) [][]int {
	result := make([][]int, 0)

	sort.Ints(nums) // 先给nums排序

	var pin1, pin2, left, right int // 固定 左 右指针
	l := len(nums)                  // 数组长度
	for i := 0; i < l-3; i++ {
        pin1 = i
        // 不要重复
		if i > 0 && nums[i] == nums[i-1] {
			continue
		}
		for j := i + 1; j < l-2; j++ {
			pin2 = j
			left = j + 1
			right = l - 1

            // 不要重复
			if j > i+1 && nums[j] == nums[j-1] {
				continue
			}

			for left < right {
                // 相等
				if nums[pin1]+nums[pin2]+nums[left]+nums[right] == target {
					result = append(result, []int{nums[pin1], nums[pin2], nums[left], nums[right]})
					for left < right && nums[left] == nums[left+1] {
						left++
					}
					for left < right && nums[right-1] == nums[right] {
						right--
					}
					left++
					right--
				} else if nums[pin1]+nums[pin2]+nums[left]+nums[right] > target {
					right--
				} else {
					left++
				}
			}
		}
	}
	return result
}
```
