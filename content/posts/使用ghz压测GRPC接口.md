---
title: "使用ghz压测GRPC接口"
author: JemmyHu(hujm20151021@gmail.com)
toc: true
mathjax: true
categories: [技术博客, 技术细节, 效率与工具]
tags: [效率, ghz, 压测GRPC接口]
comment: true
date: 2020-11-09T19:35:34+08:00
draft: false
---


## 一、前言

公司后端服务已经全部微服务化，想要调试某个服务可以使用 [`grpcui`](https://github.com/fullstorydev/grpcui)，但要对某个接口进行压测，`grpcui` 还做不到。诸多努力之后找到本次主角：[https://github.com/bojand/ghz](https://github.com/bojand/ghz)，官网：[ghz.sh](https://ghz.sh)。

推荐理由：简洁！可以一次性解决掉 `proto` 文件相互之间引用的烦心事！

## 二、使用

>   这里只介绍在 `Mac` 环境下的用法，其他环境请参阅官网。
>
>   另：我们仍旧使用 `GOPATH` 方式来管理包，我的： `export GOPATH=/Users/hujiaming/go `，本次测试目录为：`/Users/hujiaming/go/src/hujm.net`。

### 1. 安装

直接使用 `brew` 来安装：

```bas
brew install ghz
```

如果不成功，可以直接去 [https://github.com/bojand/ghz/releases](https://github.com/bojand/ghz/releases) 下载二进制，下载后放在 `PATH` 中即可。

**注：还需要有 `protoc` 工具。**

### 2. 生成 `protoset` 文件

如果你的 `proto` 文件中还引用了其他文件，强烈建议使用 `protoset` 方式。

假如我在如下的 `proto` 中定义一个 `GRPC服务`：

```protobuf
/**
 * @filename: api.proto
 */
syntax = "proto3";

import "github.com/mwitkow/go-proto-validators/validator.proto";
import "xxx/mms2/utils/i18n/moneypb/money.proto";
import "xxx/cm/fulfillment/offermanager/offerpb/offer.proto";
import "xxx/cm/fulfillment/offermanager/offerpb/association.proto";
import "xxx/cm/fulfillment/offermanager/offerpb/supplier.proto";
import "xxx/cm/core/price/pricepb/price.proto";

package offerpb;

service ApiService {
	rpc CreateSKUAssociations(CreateSKUAssociationsReq) returns (CreateSKUAssociationsReply) {};
}

message CreateSKUAssociationsReq {
  repeated Association associations = 1 [ (validator.field) = {repeated_count_min : 1} ];
}

message CreateSKUAssociationsReply {}

```

而 `Association` 是定义在 `"xxx/cm/fulfillment/offermanager/offerpb/association.proto”` 文件中的：

```protobuf
/**
 * @filename: association.proto
 */
syntax = "proto3";

import "github.com/mwitkow/go-proto-validators/validator.proto";
import "xxx/mms2/utils/i18n/moneypb/money.proto";
import "xxx/cm/fulfillment/offermanager/offerpb/supplier.proto";
import "xxx/cm/core/price/pricepb/price.proto";

package offerpb;

message Association {
  int64 offer_id = 1 [ (validator.field) = {int_gt : 1000000000} ];
  string sku_code = 2 [ (validator.field) = {string_not_empty : true} ];
  string author = 3 [ (validator.field) = {string_not_empty : true} ];
}
```

如果采用非 `protoset` 方式，可能要先生成 `association.pb.go`，再生成 `api.pb.go` 文件。这里我们采用 `protoset` 方式，一步到位：

```bash
protoc \ 
--include_imports \
-I. -I/usr/local/include \
-I/usr/local/go \ 
-I$GOPATH/src/github.com/grpc-ecosystem/grpc-gateway/third_party/googleapis \ 
-I$GOPATH/src \
--proto_path=. \ 
--descriptor_set_out=api.bundle.protoset \ 
api.proto
```

需要注意的点如下：

1.  如果你的 `proto` 文件中有引用，上述命令中一定要有 `include_imports` 参数；
2.  在后面运行时如果出现 `no descriptor found for "xxxxxx"`，可能是某个文件没有通过 `-I` 引用进来，记得加上重新执行。

不出意外，会在当前目录下生成 `api.bundle.protoset` 文件。

### 3. 执行压测任务

可以看一下 `ghz` 的用法：

```sh
$ ghz --help
usage: ghz [<flags>] [<host>]

Flags:
  -h, --help                   Show context-sensitive help (also try --help-long and --help-man).
      --config=                Path to the JSON or TOML config file that specifies all the test run settings.
      --proto=                 The Protocol Buffer .proto file.
      --protoset=              The compiled protoset file. Alternative to proto. -proto takes precedence.
      --call=                  A fully-qualified method name in 'package.Service/method' or 'package.Service.Method' format.
  -i, --import-paths=          Comma separated list of proto import paths. The current working directory and the directory of the protocol buffer file are automatically added to the import list.
      --cacert=                File containing trusted root certificates for verifying the server.
      --cert=                  File containing client certificate (public key), to present to the server. Must also provide -key option.
      --key=                   File containing client private key, to present to the server. Must also provide -cert option.
      --cname=                 Server name override when validating TLS certificate - useful for self signed certs.
      --skipTLS                Skip TLS client verification of the server's certificate chain and host name.
      --skipFirst=0            Skip the first X requests when doing the results tally.
      --insecure               Use plaintext and insecure connection.
      --authority=             Value to be used as the :authority pseudo-header. Only works if -insecure is used.
  -c, --concurrency=50         Number of requests to run concurrently. Total number of requests cannot be smaller than the concurrency level. Default is 50.
  -n, --total=200              Number of requests to run. Default is 200.
  -q, --qps=0                  Rate limit, in queries per second (QPS). Default is no rate limit.
  -t, --timeout=20s            Timeout for each request. Default is 20s, use 0 for infinite.
  -z, --duration=0             Duration of application to send requests. When duration is reached, application stops and exits. If duration is specified, n is ignored. Examples: -z 10s -z 3m.
  -x, --max-duration=0         Maximum duration of application to send requests with n setting respected. If duration is reached before n requests are completed, application stops and exits. Examples: -x
                               10s -x 3m.
      --duration-stop="close"  Specifies how duration stop is reported. Options are close, wait or ignore.
  -d, --data=                  The call data as stringified JSON. If the value is '@' then the request contents are read from stdin.
  -D, --data-file=             File path for call data JSON file. Examples: /home/user/file.json or ./file.json.
  -b, --binary                 The call data comes as serialized binary message or multiple count-prefixed messages read from stdin.
  -B, --binary-file=           File path for the call data as serialized binary message or multiple count-prefixed messages.
  -m, --metadata=              Request metadata as stringified JSON.
  -M, --metadata-file=         File path for call metadata JSON file. Examples: /home/user/metadata.json or ./metadata.json.
      --stream-interval=0      Interval for stream requests between message sends.
      --reflect-metadata=      Reflect metadata as stringified JSON used only for reflection request.
  -o, --output=                Output path. If none provided stdout is used.
  -O, --format=                Output format. One of: summary, csv, json, pretty, html, influx-summary, influx-details. Default is summary.
      --connections=1          Number of connections to use. Concurrency is distributed evenly among all the connections. Default is 1.
      --connect-timeout=10s    Connection timeout for the initial connection dial. Default is 10s.
      --keepalive=0            Keepalive time duration. Only used if present and above 0.
      --name=                  User specified name for the test.
      --tags=                  JSON representation of user-defined string tags.
      --cpus=8                 Number of cpu cores to use.
      --debug=                 The path to debug log file.
  -e, --enable-compression     Enable Gzip compression on requests.
  -v, --version                Show application version.

Args:
  [<host>]  Host and port to test.
```

需要关注的几个参数：

-   `--skipTLS --insecure`：如果服务不支持 `HTTPS` 的话，可以使用此参数跳过 `TLS` 验证；

-   `--protoset`：指定本次运行的 `protoset` 文件路径，即上面生成的 `api.bundle.protoset`；
-   `--call`：需要调用的方法名，格式为：`包名.服务名.方法名`。比如我要调用 `offerpb` 包下的 `ApiService` 服务的 `CreateSKUAssociations` 方法，那么 `call` 参数应该是： `--call offerpb.ApiService.CreateSKUAssociations`；
-   `--data`：本次请求的参数，通过 `jsonString` 的格式传入；
-   `--data-file`：本次请求的参数，只不过通过文件的形式传入，文件中是标准的通过 `json` 序列化后的数据； 
-   `--metadata`：`metadata` 参数，通过 `jsonString` 的格式传入；
-   `-c`：并发数，默认 50(这里有坑，具体参照官网解释：[-c](https://ghz.sh/docs/options#-c---concurrency)。虽然会其多个 `goroutine`，但是所有的 `goroutine` 会公用一个连接)；
-   `-n`：请求数，默认 200。`n` 不能小于 `c`。

假设 `ApiService`服务的地址是：`localhost:58784`。我们执行下面的命令，发起一次压测任务：

```sh
$ ghz \
--skipTLS --insecure --protoset /Users/hujiaming/go/src/hujm.net/api.bundle.protoset \
--call offerpb.ApiService.CreateSKUAssociations \
--data '{"associations":[{"sku_code": "test:6985079117562211244","offer_id": 8629237865019910744,"author": "test_by_ghz"}]}' \
-m '{"name": "test"}' \
-c 100 -n 1000 \
localhost:58784 
```

当你的请求参数比较多时，将他们放在一个文件中、然后使用 `--data-file` 参数是更好的选择：

```sh
$ cat test_data.json
{
  "associations": [
    {
      "sku_code": "test:6237052533738512496",
      "offer_id": 5655307241153104444,
      "author": "test_by_ghz"
    },
    {
      "sku_code": "test:2156276639623439583",
      "offer_id": 6360134836979240095,
      "author": "test_by_ghz"
    },
    {
      "sku_code": "test:8361104385030719827",
      "offer_id": 3705044490439993926,
      "author": "test_by_ghz"
    },
    {
      "sku_code": "test:6023087259299523902",
      "offer_id": 3776027093787512475,
      "author": "test_by_ghz"
    },
    {
      "sku_code": "test:9196748606623463644",
      "offer_id": 1506864634761125694,
      "author": "test_by_ghz"
    }
  ]
}

$ ghz \
--skipTLS --insecure --protoset /Users/hujiaming/go/src/hujm.net/api.bundle.protoset \
--call offerpb.ApiService.CreateSKUAssociations \
--data-file /Users/hujiaming/go/src/hujm.net/test_data.json \
-m '{"name": "test"}' \
-c 100 -n 1000 \
localhost:58784 
```

看下输出：

```sh
Summary:
  Count:	1000
  Total:	743.17 ms
  Slowest:	194.74 ms
  Fastest:	37.67 ms
  Average:	69.32 ms
  Requests/sec:	1345.59

Response time histogram:
  37.670 [1]	|
  53.377 [384]	|∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎
  69.084 [349]	|∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎∎
  84.791 [138]	|∎∎∎∎∎∎∎∎∎∎∎∎∎∎
  100.498 [26]	|∎∎∎
  116.205 [2]	|
  131.912 [0]	|
  147.619 [16]	|∎∎
  163.326 [33]	|∎∎∎
  179.033 [17]	|∎∎
  194.739 [34]	|∎∎∎∎

Latency distribution:
  10 % in 46.59 ms
  25 % in 49.94 ms
  50 % in 57.28 ms
  75 % in 69.51 ms
  90 % in 102.33 ms
  95 % in 163.38 ms
  99 % in 183.99 ms

Status code distribution:
  [OK]   1000 responses
```

`Summary` 的参数：

-   `Count`：完成的请求总数，包括成功的和失败的；
-   `Total`：本次请求所用的总时长，从 `ghz` 启动一直到结束；
-   `Slowest`：最慢的某次请求的时间；
-   `Fastest`：最快的某个请求的时间；
-   `Average`：`(所有请求的响应时间) / Count`。
-   `Requests/sec`：`RTS`，`Count / Total` 的值。

## 三、参考资料

-   [https://github.com/bojand/ghz](https://github.com/bojand/ghz)
-   [Simple gRPC benchmarking and load testing tool](https://ghz.sh/)