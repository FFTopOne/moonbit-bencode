# moonbit-bencode

[![CI](https://github.com/FFTopOne/moonbit-bencode/actions/workflows/ci.yml/badge.svg)](https://github.com/FFTopOne/moonbit-bencode/actions/workflows/ci.yml)

A spec-complete [bencode](https://www.bittorrent.org/beps/bep_0003.html) codec
for [MoonBit](https://www.moonbitlang.com) — the encoding behind BitTorrent
`.torrent` files, tracker traffic and the DHT protocol.

The library depends on nothing but `moonbitlang/core`.

## Features

- **Strict decoding.** Malformed integers (`i03e`, `i-0e`, `i-e`), bad length
  prefixes (`05:`), truncated payloads and trailing garbage are all rejected
  with the byte offset of the problem.
- **Canonical encoding.** Dictionary keys are emitted in raw byte-string
  order, so re-encoding a decoded value reproduces a canonical payload byte
  for byte.
- **Binary-safe.** Byte strings are stored as `Bytes`, never assumed to be
  UTF-8.
- **Streaming.** `StreamDecoder` decodes values incrementally from chunks —
  what network protocols need.
- **Full 64-bit integers.** Bencoded integers are decoded into `Int64` with
  overflow detection (`-2^63 ..= 2^63-1`).
- **Hardened against hostile input.** Container nesting is capped at 512
  levels, so an adversarial `llll...` payload yields `NestingTooDeep` instead
  of a stack overflow; fuzz-style tests assert that arbitrary bytes always end
  in a value or a `DecodeError`, never an abort.

## Usage

Add the dependency and decode a `.torrent` metainfo:

```mbt check
///|
test {
  let data = b"d8:announce3:foo4:infod6:lengthi12345e4:name4:fileee"
  let value = @moonbit-bencode.decode(data)
  let length = value.get_path([b"info", b"length"]).unwrap()
  assert_eq(length.as_int().unwrap(), 12345L)
}
```

Build values programmatically and encode them canonically:

```mbt check
///|
test {
  let dict = @moonbit-bencode.Value::dict_of([
    (
      b"announce",
      @moonbit-bencode.Value::str(b"http://tracker.example.com/announce"),
    ),
    (
      b"info",
      @moonbit-bencode.Value::dict_of([
        (b"length", @moonbit-bencode.Value::int(12345L)),
        (b"name", @moonbit-bencode.Value::str(b"ubuntu.iso")),
      ]),
    ),
  ])
  assert_eq(
    @moonbit-bencode.encode(dict),
    b"d8:announce35:http://tracker.example.com/announce4:infod6:lengthi12345e4:name10:ubuntu.isoee",
  )
}
```

Feed a stream chunk by chunk — values pop out as soon as they are complete:

```mbt check
///|
test {
  let dec = @moonbit-bencode.StreamDecoder::StreamDecoder()
  dec.feed(b"4:sp")
  assert_true(dec.try_next() is None)
  dec.feed(b"am")
  assert_eq(dec.try_next().unwrap().as_str().unwrap(), b"spam")
}
```

Errors carry the offending byte offset:

```mbt check
///|
test {
  try @moonbit-bencode.decode(b"i042e") catch {
    e => assert_eq(e.to_string(), "malformed integer literal at byte 1")
  } noraise {
    _ => panic()
  }
}
```

## CLI

A small command-line tool ships with the module. Run it from the project
root:

```sh
moon run cmd/main --target native -- decode file.torrent   # print the value tree
moon run cmd/main --target native -- check file.torrent    # validate only
moon run cmd/main --target native -- canon in out          # re-encode canonically
moon run cmd/main --target native -- roundtrip file.torrent
```

## API sketch

| Item | Purpose |
| --- | --- |
| `decode(data : Bytes) -> Value raise DecodeError` | one-shot decoder |
| `encode(value : Value) -> Bytes` | canonical encoder |
| `encode_into(buf : Buffer, value : Value)` | encode into a buffer |
| `Value::{int, str, list, dict, dict_of}` | constructors |
| `Value::{as_int, as_str, as_list, as_dict}` | typed accessors |
| `Value::get(key)` / `Value::get_path(keys)` | dictionary lookup |
| `StreamDecoder::{feed, try_next, pending, clear}` | incremental decoding |
| `DecodeError` | `suberror` with byte offsets |

## Development

```sh
moon test             # 49 tests: spec vectors, malformed input, streams, property
moon test README.mbt.md  # run the examples in this README (4 doctests)
moon fmt && moon info
```

## References

- [BEP 3: The BitTorrent Protocol Specification](https://www.bittorrent.org/beps/bep_0003.html)
  — the bencode grammar, canonical rules and the metainfo structure.
- [BEP 5: DHT Protocol](https://www.bittorrent.org/beps/bep_0005.html)
  — stream-oriented peer messages, the streaming use case.
- Implementations consulted for behaviour (not code): `bencode` for Python,
  `serde_bencode` for Rust, `bencode-go`.

## License

Apache-2.0
