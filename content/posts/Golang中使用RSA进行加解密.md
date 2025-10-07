---
title: "Golang中使用RSA进行加解密"
date: 2021-01-14T11:45:06+08:00
draft: false
author: JemmyHu(hujm20151021@gmail.com)
toc: true
mathjax: true
categories: [技术博客, 技术细节, Golang, 加密算法]
tags: [Golang, 加密算法, RSA]
---

<!-- @format -->

本文对 RSA 加密算法 的细节不做深究，仅描述大致用法。具体算法原理请阅读参考文献中的 2 和 4。

## 一、介绍

当我们谈论加解密方式时，通常有两种情形：**对称加密** 和 **非对称加密**。

对于 `对称加密`，加密和解密使用同一份秘钥，加密者必须将加密方式告知使用者，否则使用者无法解密，这就面临着 “秘钥配送问题”。

而在 `非对称加密` 中，有公钥和私钥加密使用公钥，解密使用私钥；公钥是公开的，任何人都可以获得，私钥则是保密的。只有持有私钥的人才能解开被对应公钥加密的数据。因此非对称加密算法，也称公钥加密算法。

如果公钥加密的信息只有私钥解得开，那么只要私钥不泄漏，通信就是安全的。

1977 年，三位数学家 Rivest、Shamir 和 Adleman 设计了一种算法，可以实现非对称加密。这种算法用他们三个人的名字命名，叫做 [`RSA算法`](http://zh.wikipedia.org/zh-cn/RSA加密算法)。从那时直到现在，RSA 算法一直是最广为使用的"非对称加密算法"。毫不夸张地说，**只要有计算机网络的地方，就有 RSA 算法**。

这种算法非常[可靠](http://en.wikipedia.org/wiki/RSA_Factoring_Challenge)，密钥越长，它就越难破解。根据已经披露的文献，目前被破解的最长 RSA 密钥是 768 个二进制位。也就是说，长度超过 768 位的密钥，还无法破解（至少没人公开宣布）。因此可以认为，1024 位的 RSA 密钥 基本安全，2048 位的密钥极其安全。

## 二、使用

Golang 的标准库中已经对 RSA 相关的加密算法进行了实现，这里展示基本用法 以及 使用自定义密码 的场景。

对 RSA 的使用大致分为三个步骤：

1.  `RSAGenKey` 生成公钥和私钥；
2.  `RSAEncrypt` 加密数据，传入 待加密数据 和 公钥，返回 加密后的数据；
3.  `RSADecrypt` 解密数据，传入 被加密的数据 和 私钥，返回 解密后的数据。

### 1. RSA 加密的基本用法

```go
// RSAGenKey 生成公私钥
func RSAGenKey(bits int) (pubKey, prvKey []byte, err error) {
	/*
		生成私钥
	*/
	// 1、使用RSA中的GenerateKey方法生成私钥（bits=1024基本安全，2048 极其安全）
	privateKey, err := rsa.GenerateKey(rand.Reader, bits)
	if err != nil {
		return nil, nil, err
	}
	// 2、通过X509标准将得到的RAS私钥序列化为：ASN.1 的DER编码字符串
	privateStream := x509.MarshalPKCS1PrivateKey(privateKey)
	// 3、将私钥字符串设置到pem格式块中
	block1 := &pem.Block{
		Type:  "private key",
		Bytes: privateStream,
	}
	// 4、通过pem将设置的数据进行编码，并写入磁盘文件
	// fPrivate, err := os.Create("privateKey.pem")
	// if err != nil {
	// 	return err
	// }
	// defer fPrivate.Close()
	// err = pem.Encode(fPrivate, block1)
	// if err != nil {
	// 	return err
	// }
	// 4. 有两种方式，一种是将秘钥写入文件，一种是当成返回值返回，由使用者自行决定
	prvKey = pem.EncodeToMemory(block1)

	/*
		生成公钥
	*/
	publicKey := privateKey.PublicKey
	publicStream, err := x509.MarshalPKIXPublicKey(&publicKey)
	block2 := &pem.Block{
		Type:  "public key",
		Bytes: publicStream,
	}
	// fPublic, err := os.Create("publicKey.pem")
	// if err != nil {
	// 	return err
	// }
	// defer fPublic.Close()
	// pem.Encode(fPublic, &block2)
	// 同样，可以将公钥写入文件，也可以直接返回
	pubKey = pem.EncodeToMemory(block2)
	return pubKey, prvKey, nil
}

// RSAEncrypt 对数据进行加密操作
func RSAEncrypt(src []byte, pubKey []byte) (res []byte, err error) {
	block, _ := pem.Decode(pubKey)
	// 使用X509将解码之后的数据 解析出来
	keyInit, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return
	}
	publicKey := keyInit.(*rsa.PublicKey)
	// 使用公钥加密数据
	res, err = rsa.EncryptPKCS1v15(rand.Reader, publicKey, src)
	return
}

// 对数据进行解密操作
func RSADecrypt(src []byte, prvKey []byte) (res []byte, err error) {
	// 解码
	block, _ := pem.Decode(prvKey)
	blockBytes := block.Bytes
	privateKey, err := x509.ParsePKCS1PrivateKey(blockBytes)
	// 还原数据
	res, err = rsa.DecryptPKCS1v15(rand.Reader, privateKey, src)
	return
}
```

看一个 demo:

```go
func main() {
    sourceData := "我的头发长，天下我为王"
	// 创建公私钥
	pubKey, prvKey, err := RSAGenKey(2048)
	if err != nil {
		panic(err)
	}
	fmt.Println("gen pubKey and prvKey ok!")
	fmt.Printf("before encrypt: %s\n", sourceData)
	// 使用公钥加密
	encryptData, err := RSAEncrypt([]byte(sourceData), pubKey)
	if err != nil {
		panic(err)
	}
	fmt.Printf("after encrypt: %v\n", encryptData)
	// 使用私钥解密
	decryptData, err := RSADecrypt(encryptData, prvKey)
	if err != nil {
		panic(err)
	}
	fmt.Printf("after decrypt: %s\n", string(decryptData))
	fmt.Printf("equal? %v \n", string(decryptData) == sourceData)
}

// 输出
gen pubKey and prvKey ok!
before encrypt: 我的头发长，天下我为王
after encrypt: [153 1 185 195 ...(很长的字节数组)]
after decrypt: 我的头发长，天下我为王
equal? true
```

### 2. 使用自定义密码的 RSA 算法

有时候我们想在随机生成的基础上加上自定义的密码，可以使用下面的方式：

```go
// RSAGenKeyWithPwd generate rsa pair key with specified password
func RSAGenKeyWithPwd(bits int, pwd string) (pubKey, prvKey []byte, err error) {
	/*
		生成私钥
	*/
	// 1、使用RSA中的GenerateKey方法生成私钥
	privateKey, err := rsa.GenerateKey(rand.Reader, bits)
	if err != nil {
		return nil, nil, err
	}
	// 2、通过X509标准将得到的RAS私钥序列化为：ASN.1 的DER编码字符串
	privateStream := x509.MarshalPKCS1PrivateKey(privateKey)
	// 3、将私钥字符串设置到pem格式块中
	block1 := &pem.Block{
		Type:  "private key",
		Bytes: privateStream,
	}
	// 通过自定义密码加密
	if pwd != "" {
		block1, err = x509.EncryptPEMBlock(rand.Reader, block1.Type, block1.Bytes, []byte(pwd), x509.PEMCipherAES256)
		if err != nil {
			return nil, nil, err
		}
	}
	prvKey = pem.EncodeToMemory(block1)

	/*
		生成公钥
	*/
	publicKey := privateKey.PublicKey
	publicStream, err := x509.MarshalPKIXPublicKey(&publicKey)
	block2 := &pem.Block{
		Type:  "public key",
		Bytes: publicStream,
	}
	pubKey = pem.EncodeToMemory(block2)
	return pubKey, prvKey, nil
}

// 加密方式与 RSAEncrypt 没有区别，可以共用

// RSADecryptWithPwd decrypt src with private key and password
func RSADecryptWithPwd(src []byte, prvKey []byte, pwd string) (res []byte, err error) {
	// 解码
	block, _ := pem.Decode(prvKey)
	blockBytes := block.Bytes
	if pwd != "" {
		blockBytes, err = x509.DecryptPEMBlock(block, []byte(pwd))
		if err != nil {
			return nil, err
		}
	}
	privateKey, err := x509.ParsePKCS1PrivateKey(blockBytes)
	// 还原数据
	res, err = rsa.DecryptPKCS1v15(rand.Reader, privateKey, src)
	return
}

```

看一个 demo：

```go
func main() {
    sourceData := "好的代码本身就是最好的说明文档"
	pwd := "123456"
	// 创建公私钥
	pubKey, prvKey, err := RSAGenKeyWithPwd(2048, pwd)
	if err != nil {
		panic(err)
	}
	fmt.Println("gen pubKey and prvKey ok!")
	fmt.Printf("before encrypt: %s\n", sourceData)
	// 使用公钥加密
	encryptData, err := RSAEncrypt([]byte(sourceData), pubKey)
	if err != nil {
		panic(err)
	}
	fmt.Printf("after encrypt: %v\n", encryptData)
	// 使用私钥解密
	decryptData, err := RSADecryptWithPwd(encryptData, prvKey, pwd)
	if err != nil {
		panic(err)
	}
	fmt.Printf("after decrypt: %s\n", string(decryptData))
	fmt.Printf("equal? %v \n", string(decryptData) == sourceData)
}

// 输出
gen pubKey and prvKey ok!
before encrypt: 好的代码本身就是最好的说明文档
after encrypt: [136 134 26 233 ...(很长的字节数组)]
after decrypt: 好的代码本身就是最好的说明文档
equal? true
```

## 参考文章：

- [golang 使用 RSA 生成公私钥，加密，解密，并使用 SHA256 进行签名，验证](https://studygolang.com/articles/22530)
- [GO 语言 RSA 加密解密](https://wumansgy.github.io/2018/10/18/GO%E8%AF%AD%E8%A8%80RSA%E5%8A%A0%E5%AF%86%E8%A7%A3%E5%AF%86/)
- [go - 如何在 golang 中使用密码创建 rsa 私钥](https://www.coder.work/article/194272)
- [RSA 算法原理（一）](https://www.ruanyifeng.com/blog/2013/06/rsa_algorithm_part_one.html)
