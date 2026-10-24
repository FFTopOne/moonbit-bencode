# moonbit-bencode 项目申报书

## 基本信息

- 项目名称：moonbit-bencode：Bencode（BEP 3）的 MoonBit 编解码库
- 参赛者：张熠飞
- 联系方式：GitHub @FFTopOne（完整联系方式见报名表，不在公开仓库中留存）
- GitHub 仓库链接：<https://github.com/FFTopOne/moonbit-bencode>
- 项目方向：MoonBit 数据编解码基础库 / 二进制协议基础设施
- 是否为移植项目：否（原创项目，十月赛新项目）

## 项目简介

MoonBit 生态已有 `moon_bencode`（mooncakes：`2515050243qyf/moon_bencode`），覆盖编解码、

种子元信息、磁力链接与 info hash。本项目不重复这些能力，而是补齐 BEP 3 规范中它尚未覆盖的

部分：**无界整数**（BEP 3 不限制整数大小，既有实现遇 Int64 越界即报错）、**增量流式解码**

（DHT/Krpc 的 UDP 场景需要，既有实现仅支持一次性 `decode`）、**逐字节偏移的错误定位**与

**对抗性输入防护**，并在此之上提供 Tracker 响应的类型化解析。项目定位为「BEP 3 编解码语义

层」，专注规范本身而非种子业务封装。

## 与 moon_bencode 的关系

- **代码关系**：未使用、未复制其代码。实现以 BEP 3 规范文本为准；其行为口径已逐条对照源码

  核对（同样拒绝前导零与非规范整数、同样按原始字节序输出键、同样拒绝拖尾字节），因此同一

  载荷在两种实现下得到同一结果。
- **本项目的独立核心范围**（对方未覆盖，且四项构成闭环而非附加功能）：
  1. 无界整数：`BigInt`（符号 + 规格化十进制位）承载任意长度整数，解码不再拒绝越界值；
  2. 增量流式解码：`StreamDecoder` 分块喂入、值完整即产出，面向无长度前缀的 UDP 协议流；
  3. 规范可复现性：解码后重编码逐字节一致，是 info hash 等下游计算的前提；
  4. 可诊断性与健壮性：每个错误携带字节偏移；嵌套超 512 层报 `NestingTooDeep` 而非栈溢出。
- **明确不覆盖的部分**（交由 moon_bencode，避免重复建设）：零拷贝视图、JSON 互操作、磁力

  链接解析、info hash 计算。

## 使用场景

1. **种子文件解析**：读取 `announce`、`info.name`、`info.pieces` 等字段，做元信息校验、体积

   统计或转磁力链接；`canon` 子命令可把非规范种子重写为规范形式。
2. **DHT / Krpc 节点**：UDP 上多条 bencode 消息首尾相接且无长度前缀，`StreamDecoder` 分块

   喂入，消息完整即产出，`pending()` 判断是否处于消息边界。
3. **大整数与互操作校验**：BEP 3 未限制整数大小，真实生态存在超出 64 位的载荷；本项目不拒绝

   这类值，可按需读取（`as_int` / `as_integer` / `as_bigint`），也可用于校验其他实现对大整数

   的处理是否正确。

## 核心功能范围

- 提供 `Value` 模型（整数 / 无界整数 / 字节串 / 列表 / 字典）；字典保留插入顺序、重复键后者

  覆盖、相等性比较忽略键序；
- 提供 `BigInt` 任意精度整数：`parse` / `to_int64` / `from_int64`，规格化表示无精度损失，

  1000 位整数往返一致；`Value::int(5)` 与 `Value::big_int(...)` 按值相等；
- 提供一次性 `decode`，拒绝 `i03e`、`i-0e`、`05:` 等非规范输入；截断载荷、非字符串键、拖尾

  字节各有对应错误，且携带字节偏移；
- 提供规范编码 `encode` / `encode_into`：整数取最短形式，字典键按原始字节序排序；
- 提供 `StreamDecoder::{feed, try_next, pending, clear}`，缓冲区超 4096 字节自动压缩；
- 提供对抗性输入防护：容器嵌套上限 512 层，超限报 `NestingTooDeep`（实测 20 万层恶意载荷

  仍能优雅报错）；
- 提供 Tracker 响应类型 `AnnounceResponse::parse` 与 `Peer` 地址类型（IPv4 / IPv6 三种

  peers 编码）；
- 提供 CLI：`decode` / `check` / `canon` / `roundtrip` 四个子命令；
- 提供 70+ 个 MoonBit 测试（规范向量、畸形输入逐项断言、流式逐字节喂入、800 组随机字节「不

  panic」、300 组随机值往返含大整数）与 `moon bench --release` 基准（decode 3.2 µs / encode

  2.8 µs）；
- README 示例全部由 doctest 真实执行；GitHub Actions 每次推送执行格式检查、零警告类型检查、

  全部测试与文档测试。

## 原创性与参考说明

- 是否原创：**是**。从零用 MoonBit 编写，未复制任何现有实现代码；Git 历史自初始提交起完整

  可查，共 20+ 个有效提交（无空提交、无重复提交、无无意义拆分）。
- 既有同类实现：`moon_bencode`（<https://gitlink.org.cn/qyf795201/moon-bencode）。本项目与其>

  为**互补关系**而非重复建设，差异见上一节，且均可由仓库内的公开 API 与测试核验。
- 参考规范：BEP 3（<https://www.bittorrent.org/beps/bep_0003.html）、BEP> 5

  （<https://www.bittorrent.org/beps/bep_0005.html）；Python> / Rust / Go 的同名实现仅作行为

  对照，无代码引用。
- 本项目许可证：Apache-2.0。

## 实际结构（部分）

```
moonbit-bencode/
├── moonbit-bencode.mbt   公开 API（decode / encode / StreamDecoder）
├── value.mbt  decoder.mbt  encoder.mbt  tracker.mbt  errors.mbt  bigint.mbt
├── cli/  cmd/main/       CLI 逻辑与可执行入口
├── *_test.mbt            70+ 个测试 + 基准套件
└── .github/workflows/    GitHub Actions CI
```
