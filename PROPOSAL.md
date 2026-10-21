# moonbit-bencode 项目申报书

## 基本信息

- 项目名称：moonbit-bencode：Bencode（BEP 3）的 MoonBit 编解码库
- 参赛者：`[请填写姓名或昵称]`（GitHub ID：FFTopOne）
- 联系方式：`[请填写手机或邮箱]`
- GitHub 仓库链接：https://github.com/FFTopOne/moonbit-bencode
- 项目方向：MoonBit 数据编解码基础库 / 二进制协议基础设施
- 是否为移植项目：否（原创项目，十月赛新项目）

## 项目简介

bencode 是 BitTorrent 生态的基础编码，`.torrent` 种子、Tracker 通信与 DHT（Krpc）协议都用它；
而 MoonBit 官方注册表（mooncakes.io）与 moonbitlang 官方仓库目前没有任何 bencode 实现
（2026-10-21 核查）。本项目为需要处理 BitTorrent 数据的库作者、工具开发者与教学项目提供规范
完整、可直接依赖的编解码层：严格解码（错误带字节偏移）、规范编码（可逐字节复现载荷）、增量
流式解码与 Tracker 响应类型化解析，配套 CLI、66 个测试与基准套件。

## 使用场景

1. **种子文件解析工具**：读取 `announce`、`info.name`、`info.pieces` 等字段，做元信息校验、
   体积统计或转磁力链接；`canon` 子命令可把非规范种子重写为规范形式。
2. **DHT / Krpc 节点**：UDP 上多条 bencode 消息首尾相接且无长度前缀，用 `StreamDecoder` 分块
   喂入，消息完整即产出，`pending()` 判断是否处于消息边界。
3. **Tracker 客户端**：`AnnounceResponse::parse` 取出 `interval`、`complete`、`incomplete`，
   peers 支持紧凑 IPv4（BEP 23）、紧凑 IPv6 与 `{ip, port}` 字典列表三种形态，地址保持二进制。

## 核心功能范围

- 提供 `Value` 数据模型，一一映射 bencode 的整数、字节串、列表、字典四种类型；字典保留插入
  顺序，重复键后者覆盖，相等性比较忽略键序；
- 提供一次性解码 `decode(Bytes) -> Value`，拒绝 `i03e`、`i-0e`、`i-e`、`05:` 等非规范输入，
  截断载荷、非字符串键、拖尾字节各有对应错误，且携带字节偏移；
- 提供规范编码 `encode(Value) -> Bytes` 与 `encode_into(Buffer, Value)`：整数取最短形式，
  字典键按原始字节序排序，解码后再编码可逐字节复现规范载荷；
- 提供增量流式解码 `StreamDecoder::{feed, try_next, pending, clear}`，分块输入、值完整即产出，
  缓冲区超 4096 字节自动压缩；
- 支持完整 64 位整数（−2^63 ..= 2^63−1），溢出报 `IntegerOverflow`，负边界以 UInt64 折叠
  精确表示；
- 提供对抗性输入防护：容器嵌套上限 512 层，超限报 `NestingTooDeep` 而非栈溢出（实测 20 万层
  恶意载荷仍能优雅报错）；
- 提供 Tracker 响应类型 `AnnounceResponse::parse`，解析 `interval`、`min interval`、
  `complete`、`incomplete`、`failure reason` 与三种 peers 编码；`Peer` 以原始字节保存
  IPv4/IPv6 地址，仅在展示时由 `ip_string()` 格式化；
- 提供 CLI：`decode` / `check` / `canon` / `roundtrip` 四个子命令，可用于种子库批量校验；
- 提供 66 个 MoonBit 测试（BEP 3 规范向量、畸形输入、流式逐字节喂入、800 组随机字节“不
  panic”、300 组随机值往返）与 `moon bench --release` 基准；README 示例全部由 doctest 执行；
  GitHub Actions 在每次推送跑格式检查、零警告类型检查、测试与文档测试。

## 原创性与参考说明

- 是否原创：**是**。从零用 MoonBit 编写，未复制任何现有实现代码；Git 历史自初始提交起完整可
  查，共 20+ 个有效提交（无空提交、无重复提交、无无意义拆分）。
- 参考规范：BEP 3（https://www.bittorrent.org/beps/bep_0003.html）、BEP 5
  （https://www.bittorrent.org/beps/bep_0005.html）；相邻实现（Python `bencode`、Rust
  `serde_bencode`、Go `bencode-go`）仅作行为对照，无代码引用。
- 与相邻格式的差异：JSON / JSON5 为文本格式，CBOR 服务不同协议，BitTorrent 生态只识别 bencode。
- 实现取舍：整数以 Int64 表达并拒绝越界（规范未限界，实际载荷远低于此）；嵌套 512 层上限换取
  可控栈深度；解码对字典键序宽松、编码始终输出规范序，兼顾兼容性与可复现性。
- 本项目许可证：Apache-2.0。

## 实际结构（部分）

```
moonbit-bencode/
├── moonbit-bencode.mbt   公开 API（decode / encode / StreamDecoder）
├── value.mbt  decoder.mbt  encoder.mbt  tracker.mbt  errors.mbt
├── cli/  cmd/main/       CLI 逻辑与可执行入口
├── *_test.mbt            66 个测试 + 基准套件
└── .github/workflows/    GitHub Actions CI
```
