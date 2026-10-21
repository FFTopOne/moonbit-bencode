// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "your-github-id/moonbit-bencode"

version = "0.1.0"

readme = "README.mbt.md"

repository = ""

license = "Apache-2.0"

keywords = [
  "bencode",
  "bittorrent",
  "torrent",
  "codec",
  "parser",
  "serialization",
  "dht",
]

preferred_target = "wasm"

description = "A spec-complete bencode (BEP 3) codec for MoonBit: strict decoder with byte offsets, canonical encoder, and an incremental stream decoder."

import {
  "moonbitlang/x@0.5.6",
}
