# moonbit-bencode 项目申报书

## 1. 项目名称

moonbit-bencode —— MoonBit 的 Bencode（BEP 3）编解码库

## 2. 项目简介

bencode 是 BitTorrent 生态的基础编码：`.torrent` 种子文件、Tracker 通信与 DHT 协议都用它。
MoonBit 官方注册表（mooncakes.io）与 moonbitlang 官方仓库中目前没有任何 bencode 实现
（2026-10-21 核查），用 MoonBit 写 BitTorrent 工具只能手写解析器；而 bencode 规则苛刻（整数
禁止前导零、字典键须按原始字节序、字符串按字节计长且不保证 UTF-8），手写极易出错。本项目
从零实现一个可直接依赖的编解码库：严格解码（错误带字节偏移）、规范编码、增量流式解码，
配套 CLI 与 55 个自动化测试。

## 3. 项目方向与通用性说明

**方向：工具库**（协议库与可复用基础组件），兼有数据处理（二进制格式解析）属性。

- 不绑定 BitTorrent 业务，是纯编解码层，任何需要紧凑二进制序列化的 MoonBit 程序都可依赖；
- 纯 MoonBit 实现，仅依赖 `moonbitlang/core`，支持 wasm / wasm-gc / js / native 多后端；
- 与传输层解耦：一次性 `decode` 面向文件，`StreamDecoder` 面向无长度前缀的字节流；
- 字节串以 `Bytes` 处理（二进制安全），可承载哈希、片段等任意载荷。

## 4. 预期使用场景

1. **种子文件解析**：读取 `.torrent` 的 `announce`、`info.length`、`info.pieces` 等字段，做元
   信息校验、体积统计或转磁力链接；`canon` 子命令可把非规范种子重写为规范形式。
2. **DHT / Krpc 节点**：UDP 上多条 bencode 消息首尾相接且无长度前缀，用 `StreamDecoder` 分块
   喂入，消息完整即产出，`pending()` 判断是否处于消息边界。
3. **Tracker 客户端**：解析 announce 响应（`interval`、`complete`、`peers` 紧凑列表），peer 的
   4 字节 IPv4 + 2 字节端口保持二进制，无需先转字符串。

## 5. 拟实现的核心功能（首期已全部实现并通过测试）

- **严格解码**：拒绝 `i03e`、`i-0e`、`05:` 等非规范输入；截断载荷、非字符串键、拖尾字节均有
  对应错误且带字节偏移；整数覆盖 −2^63 ..= 2^63−1，溢出即报错；
- **规范编码**：整数取最短形式，字典键按原始字节序排序，解码→编码可逐字节复现规范载荷；
- **增量流式解码**：分块输入，值完整即产出，缓冲区超 4096 字节自动压缩；
- **对抗输入防护**：容器嵌套上限 512 层，恶意 `llll…` 载荷返回 `NestingTooDeep` 而非栈溢出；
- **值访问 API**：`as_int` / `as_str` / `as_list` / `as_dict`、`get`、`get_path` 嵌套查找；
- **Tracker 响应类型**：`AnnounceResponse::parse` 解析 interval / complete / incomplete /
  failure reason 与 peers（紧凑 IPv4、紧凑 IPv6、字典列表三种形态）；
- **CLI**：`decode` / `check` / `canon` / `roundtrip` 四个子命令。

## 6. 项目类型

**原创项目（非移植），且为十月赛新项目（非社区维护项目）**：从零用 MoonBit 编写，Git 历史自
初始提交起完整可查，未复制任何现有实现代码。与相邻格式不重叠——JSON / JSON5 为文本格式，
CBOR 服务不同协议，而 BitTorrent 生态只识别 bencode。bencode 编解码功能在 Python / Rust / Go
生态已有实现，本项目以 **BEP 3 规范文本**为准，仅对照其行为做交叉验证，无代码引用。

## 7. 移植说明

本项目非移植项目，本项不适用。为便于评审核查，仍列出规范来源：BEP 3
（https://www.bittorrent.org/beps/bep_0003.html）、BEP 5
（https://www.bittorrent.org/beps/bep_0005.html）。项目采用 Apache-2.0 许可证。

## 8. GitHub 仓库

https://github.com/FFTopOne/moonbit-bencode （公开，默认分支 `main`，Apache-2.0）

- **有效提交 20+ 个**（要求 ≥10），无空提交、无重复提交、无无意义拆分；每个提交是一次独立可
  验证的改动：骨架 → 类型 → 解码器 → 编码器 → 测试 → CLI → 文档 → 嵌套防护 → CI → DHT 示例。
- 另有 5 个 Issue（4 开放、1 关闭）与 1 个已合并 PR（经 CI 校验），协作记录可追溯。
- GitHub Actions 每次推送执行格式检查、零警告类型检查、全部测试与文档测试，当前全绿。
