---
title: "虚拟网络设备tuntap"
author: JemmyHu(hujm20151021@gmail.com)
toc: true
mathjax: true
categories: [技术博客, 技术细节, 底层原理]
tags: [底层原理, tun/tap, VPN]
date: 2020-11-16T20:25:50+08:00
draft: false
---

> 实验机器：`MacBook Pro (Retina, 15-inch, Mid 2015)`
>
> Golang 版本：`go version go1.14.6 darwin/amd64`

## 一、前言

**网卡** 也称 **网络适配器**，是电脑与局域网进行相互连接的设备，在 `OSI` 七层模型中，工作在 **物理层** 和 **数据链路层**，其作用可以简单描述为：

1.  将本机的数据封装成帧，通过网线**发送**到网络上去；
2.  **接收**网络上其他设别传过来的帧，将其重新组合成数据，向上层传输到本机的应用程序中。

这里的网卡指的是真实的网卡，是一个真实的物理设备。今天我们要了解的是一个叫 **虚拟网卡** 的东西。

在当前的云计算时代，虚拟机和容器的盛行离不开网络管理设备，即 **虚拟网络设备**，或者说是 **虚拟网卡**。虚拟网卡有以下好处：

1.  对用户来说，虚拟网卡和真实网卡几乎没有区别。我们对虚拟网卡的操作不会影响到真实的网卡，不会影响到本机网络；
2.  虚拟网卡的数据可以直接从用户态读取和写入，这样方便我们在用户态进行一些额外的操作(比如截包、修改后再发送出去)

Linux 系统中有众多的虚拟网络设备，如 `TUN/TAP 设备`、`VETH 设备`、`Bridge 设备`、`Bond 设备`、`VLAN 设备`、`MACVTAP 设备` 等。这里我们只关注 `TUN/TAP 设备`。

`tap/tun` 是 `Linux` 内核 `2.4.x` 版本之后实现的虚拟网络设备，不同于物理网卡靠硬件网路板卡实现，**`tap/tun` 虚拟网卡完全由软件来实现**，功能和硬件实现完全没有差别，它们都属于网络设备，都可以配置 IP，都归 Linux 网络设备管理模块统一管理。

## 二、理解 `tun/tap` 数据传输过程

**TUN** 设备是一种虚拟网络设备，通过此设备，程序可以方便地模拟网络行为。**TUN** 模拟的是一个三层设备(`OSI` 模型的第三层：网络层，即IP 层),也就是说，通过它可以处理来自网络层的数据，更通俗一点的说，通过它，通过它我们可以处理 **IP** 数据包。

先看一下正常情况下的物理设备是如何工作的：

![物理设备](https://tva1.sinaimg.cn/large/0081Kckwgy1gkp4p8argmj30wl0u01kx.jpg)

这里的 `ethx` 表示的就是一台主机的真实的网卡接口，一般一台主机只会有一块网卡，像一些特殊的设备，比如路由器，有多少个口就有多少块网卡。

我们先看一下 `ifconfig` 命令的输出：

```sh
$ ifconfig
...
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	options=400<CHANNEL_IO>
	ether ac:bc:32:96:86:01
	inet6 fe80::456:7cb8:3dc5:2722%en0 prefixlen 64 secured scopeid 0x4
	inet 10.0.0.176 netmask 0xffffff00 broadcast 10.0.0.255
	nd6 options=201<PERFORMNUD,DAD>
	media: autoselect
	status: active
...
```

可以看到 `etho` 这个网卡接口分配到的 IP 地址是 `10.0.0.176`，这是一块物理网卡，它的两端分别是 **内核协议栈** 和 **外面的网络**，从物理层收到的数据，会被转发给内核进而通过某种接口被应用层的用户程序读到；应用程序要想和网络中的另一个进程进行数据通信，会先将数据发送给内核，然后被网卡发送出去。

接下来我们看一看 `tun/tap` 设备的工作方式：

![tun工作方式](https://tva1.sinaimg.cn/large/0081Kckwgy1gkp5pk467sj30we0u0h6p.jpg)

上图中应用层有两个应用程序，而 **网络协议栈** 和 **网络设备(`eth0` 和 `tun0`)** 都位于内核层，对于 `socket`，可以这么理解：`socket` 就像是一组 `接口(interface)`，它将更复杂的 `TCP/IP` 协议簇隐藏在 `socket` 接口后面，只对用户暴露更简单的接口，就像操作系统隐藏了底层的硬件操作细节而只对用户程序暴露接口一样，它是 应用层 与 `TCP/IP`协议簇 通信的中间软件抽象层。

`tun0` 就是一个 `tun/tap` 虚拟设备，从上图中就可以看出它和物理设备 `eth0` 的区别：虽然它们的一端都是连着网络协议栈，但是 `eth0` 另一端连接的是物理网络，而 `tun0` 另一端连接的是一个 **应用层程序**，这样协议栈发送给 `tun0` 的数据包就可以被这个应用程序读取到，此时这个应用程序可以对数据包进行一些自定义的修改(比如封装成 `UDP`)，然后又通过网络协议栈发送出去——这就是目前大多数 **代理** 的工作原理。

假如 `eth0` 的 IP 地址是 `10.0.0.176`，而 `tun0` 配的 IP 为 `192.168.1.2`。上图是一个典型的使用 `tun/tap` 进行 `VPN` 工作的原理，发送给 `192.168.1.0/24` 的数据通过 `应用程序 B` 这个 **隧道** 处理(隐藏一些信息)之后，利用真实的物理设备 `10.0.0.176` 转发给目的地址(假如为 `49.233.198.76`)，从而实现 `VPN`。我们看下每一个流程：

1.  `Application A` 是一个普通的应用程序，通过 `Socket A` 发送了一个数据包，这个数据包的目的地址是 `192.168.1.2`；
2.  `Socket A` 将这个数据包丢给网络协议栈；
3.  协议栈根据数据包的目的地址，匹配本地路由规则，得知这个数据包应该由 `tun0` 出去，于是将数据包丢给了 `tun0`；
4.  `tun0` 收到数据包之后，发现另一端被 `Application B` 打开，于是又将数据包丢给了 `Application B`；
5.  `Application B` 收到数据包之后，解包，做一些特殊的处理，然后构造一个新的数据包，将原来的数据嵌入新的数据包中，最后通过 `Socket B` 将数据包转发出去，这个时候新数据包的源地址就变成了 `eth0` 的地址，而目的地址就变成了真正想发送的主机的地址，比如 `49.233.198.76`；
6.  `Socket B` 将这个数据包丢给网络协议栈；
7.  协议栈根据本地路由得知，这个数据包应该从 `eth0` 发送出去，于是将数据包丢给 `eth0`；
8.  `eth0` 通过物理网络将这个数据包发送出去

简单来说，`tun/tap` 设备的用处是将协议栈中的部分数据包转发给用户空间的特殊应用程序，给用户空间的程序一个处理数据包的机会，比较常用的场景是 **数据压缩**、**加密**等，比如 `VPN`。

## 三、使用 `Golang` 实现一个简易 `VPN`

先看客户端的实现：

```go
package main

import (
	"encoding/binary"
	"net"
	"os"
	"os/signal"
	"syscall"

	"github.com/fatih/color"
	"github.com/songgao/water"
	flag "github.com/spf13/pflag"
)

/*
* @CreateTime: 2020/11/16 11:08
* @Author: hujiaming
* @Description:
数据传输过程：
	用户数据，如ping --> 协议栈conn --> IfaceWrite --> IfaceRead --> 协议栈conn --> 网线
*/

var (
	serviceAddress = flag.String("addr", "10.0.0.245:9621", "service address")
	tunName        = flag.String("dev", "", "local tun device name")
)

func main() {
	flag.Parse()

	// create tun/tap interface
	iface, err := water.New(water.Config{
		DeviceType: water.TUN,
		PlatformSpecificParams: water.PlatformSpecificParams{
			Name: *tunName,
		},
	})
	if err != nil {
		color.Red("create tun device failed,error: %v", err)
		return
	}

	// connect to server
	conn, err := net.Dial("tcp", *serviceAddress)
	if err != nil {
		color.Red("connect to server failed,error: %v", err)
		return
	}

	//
	go IfaceRead(iface, conn)
	go IfaceWrite(iface, conn)

	sig := make(chan os.Signal, 3)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGABRT, syscall.SIGHUP)
	<-sig
}

/*
	IfaceRead 从 tun 设备读取数据
*/
func IfaceRead(iface *water.Interface, conn net.Conn) {
	packet := make([]byte, 2048)
	for {
		// 不断从 tun 设备读取数据
		n, err := iface.Read(packet)
		if err != nil {
			color.Red("READ: read from tun failed")
			break
		}
		// 在这里你可以对拿到的数据包做一些数据，比如加密。这里只对其进行简单的打印
		color.Cyan("get data from tun: %v", packet[:n])

		// 通过物理连接，将处理后的数据包发送给目的服务器
		err = forwardServer(conn, packet[:n])
		if err != nil {
			color.Red("forward to server failed")
		}
	}
}

/*
	IfaceWrite 从物理连接中读取数据，然后通过 tun 将数据发送给 IfaceRead
*/
func IfaceWrite(iface *water.Interface, conn net.Conn) {
	packet := make([]byte, 2048)
	for {
		// 从物理请求中读取数据
		nr, err := conn.Read(packet)
		if err != nil {
			color.Red("WRITE: read from tun failed")
			break
		}

		// 将处理后的数据通过 tun 发送给 IfaceRead
		_, err = iface.Write(packet[4:nr])
		if err != nil {
			color.Red("WRITE: write to tun failed")
		}
	}
}

// forwardServer 通过物理连接发送一个包
func forwardServer(conn net.Conn, buff []byte) (err error) {
	output := make([]byte, 0)
	bsize := make([]byte, 4)
	binary.BigEndian.PutUint32(bsize, uint32(len(buff)))

	output = append(output, bsize...)
	output = append(output, buff...)

	left := len(output)
	for left > 0 {
		nw, er := conn.Write(output)
		if er != nil {
			err = er
		}

		left -= nw
	}

	return err
}
```

再看服务端的实现：

```go
package main

import (
	"io"
	"net"

	"github.com/fatih/color"
)

/*
* @CreateTime: 2020/11/16 11:39
* @Author: hujiaming
* @Description:
 */

var clients = make([]net.Conn, 0)

func main() {
	listener, err := net.Listen("tcp", ":9621")
	if err != nil {
		color.Red("listen failed,error: %v", err)
		return
	}
	color.Cyan("server start...")
	for {
        // 对客户端的每一个连接，都起一个 go 协程去处理
		conn, err := listener.Accept()
		if err != nil {
			color.Red("tcp accept failed,error: %v", err)
			break
		}
		clients = append(clients, conn)
		color.Cyan("accept tun client")
		go handleClient(conn)
	}
}

func handleClient(conn net.Conn) {
	defer conn.Close()
	buff := make([]byte, 65536)
	for {
		n, err := conn.Read(buff)
		if err != nil {
			if err != io.EOF {
				color.Red("read from client failed")
			}
			break
		}
		// broadcast data to all clients
		for _, c := range clients {
			if c.RemoteAddr().String() != conn.RemoteAddr().String() {
				c.Write(buff[:n])
			}
		}
	}
}
```
在这里，我们把 **网络协议栈** 抽象成了一个黑盒。在接下来的步骤中，我们将逐渐抽丝剥茧，一步步了解网络协议栈的工作原理，以及用 Golang 去实现它。
## 四、参考

- [原创 详解云计算网络底层技术——虚拟网络设备 tap/tun 原理解析](https://www.cnblogs.com/bakari/p/10450711.html)
- [TUN/TAP概述及操作](https://blog.liu-kevin.com/2020/01/06/tun-tapshe-bei-qian-xi/)
- [TUN/TAP设备浅析](https://www.jianshu.com/p/09f9375b7fa7)
- [https://github.com/ICKelin/article/issues/9](https://github.com/ICKelin/article/issues/9)