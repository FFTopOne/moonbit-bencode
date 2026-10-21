# 一页项目说明：moonbit-bencode

## 项目是什么

`moonbit-bencode` 是一个符合 [BEP 3 规范](https://www.bittorrent.org/beps/bep_0003.html)的
bencode 编解码库。bencode 是 BitTorrent 生态的基础编码：`.torrent` 文件、Tracker 通信和
DHT 协议都使用它。MoonBit 生态中此前没有任何 bencode 实现，本项目填补这一空白。

- **主要实现语言**：MoonBit（仅依赖 `moonbitlang/core`）
- **项目类型**：原创开源库（非移植）
- **许可证**：Apache-2.0

## 解决的真实问题

任何用 MoonBit 编写 BitTorrent 相关工具（种子解析、Tracker、DHT 客户端、自制下载器）的
开发者，都需要一个可靠的数据层。bencode 规则苛刻：整数不允许前导零、字典键必须按原始
字节序排列、字符串按字节计长且不保证是 UTF-8。手写解析器容易在这些细节上出错，而错误
的数据层会让上层工具难以调试。本库把规范细节收敛到一处，并提供带字节偏移的错误定位。

## 功能清单（均已实现并通过测试）

1. **严格解码器**：拒绝 `i03e`、`i-0e`、`i-e`、`05:` 等非规范输入；截断载荷、字典非
   字符串键、拖尾字节均有对应错误；每个错误携带字节偏移。
2. **规范编码器**：整数取最短形式，字典键按原始字节序输出——解码后重新编码可与规范
   载荷逐字节一致（已用真实 `.torrent` 样例验证）。
3. **完整的 64 位整数**：范围 `-2^63 ..= 2^63-1`，溢出即报错（量级以 UInt64 折叠，
   保证 `Int64` 最小值可精确表示）。
4. **二进制安全**：字节串以 `Bytes` 存储，不假设 UTF-8。
5. **流式解码器**：`StreamDecoder` 支持分块输入，值一旦完整立即产出；内部缓冲区超
   4096 字节自动压缩，可无限长流。
6. **命令行工具**：`decode` / `check` / `canon` / `roundtrip` 四个子命令。

## 技术方案

- 递归下降解析，游标（Cursor）直接作用于 `BytesView`，字节串零拷贝切片后按需持有。
- `Value` 枚举一一映射 bencode 的四种类型；字典用 `LinkedHashMap`，保留首次插入顺序，
   重复键后者覆盖。
- 错误处理使用 MoonBit 的 `suberror` + `raise` 机制，调用方零成本传播。
- `Show` / `Debug` 渲染让二进制载荷在日志和测试快照中可读。

## 质量保障

- **46 个测试全部通过**（`moon test`）：BEP 3 规范向量、规范往返、畸形输入逐项断言、
   流式解码（含逐字节喂入与压缩路径）、xorshift 确定性属性测试（300 组随机值往返）、
   渲染与相等性边界。
- README 中的示例由 `moon test` 作为 doctest 真实执行。
- `moon check` 零警告；`moon fmt` / `moon info` 规范提交。
- 开发记录：7 个语义化提交，从骨架到测试逐步可追踪。

## 交付计划

项目已按报名要求完成首期交付（解码、编码、流式、CLI、测试、文档）。后续计划：发布到
mooncakes.io 注册表；补充 BEP 3 之外的 Tracker 协议辅助类型； benchmark 套件。

## 团队

个人参赛（队长 1 人，无队友）。GitHub ID：FFTopOne
