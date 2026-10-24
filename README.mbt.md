# moonbit-bencode

[![CI](https://github.com/FFTopOne/moonbit-bencode/actions/workflows/ci.yml/badge.svg)](https://github.com/FFTopOne/moonbit-bencode/actions/workflows/ci.yml)

A spec-complete [bencode](https://www.bittorrent.org/beps/bep_0003.html) codec
for [MoonBit](https://www.moonbitlang.com) — the encoding behind BitTorrent
`.torrent` files, tracker traffic and the DHT protocol.

The library depends on nothing but `moonbitlang/core`.

### How this relates to `moon_bencode`

The MoonBit ecosystem already has
[`moon_bencode`](https://gitlink.org.cn/qyf795201/moon-bencode), which covers
encoding/decoding, torrent metainfo, magnet links and info hashes. This
library is a **complement, not a replacement** — it covers the parts of BEP 3
that one leaves open, and deliberately does not duplicate the rest:

| | `moon_bencode` | this library |
| --- | --- | --- |
| integers beyond `Int64` | rejected | `BigInt`, lossless round trip |
| incremental decoding | — | `StreamDecoder` for length-unprefixed streams |
| error reporting | — | every error carries its byte offset |
| hostile input | — | 512-level nesting cap instead of a stack overflow |
| zero-copy views, JSON, magnet links, info hash | yes | out of scope here |

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
- **Unbounded integers.** BEP 3 puts no limit on integer size, so nothing is
  rejected: values that fit decode into `Int64` (the cheap path) and larger
  ones into `BigInt`, a normalised sign-plus-decimal-digits representation
  that round-trips exactly. `Value::int(5) == Value::big_int(...)` compares
  by value.
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

### Real-world streaming: Krpc (BEP 5)

The DHT speaks *Krpc*: bencoded messages sent back to back over one socket,
with no length prefix and no delimiter. A message therefore has to be
recognised by parsing it, which is exactly what `StreamDecoder` does — it
reports `None` until a value is complete and then hands back one message at a
time.

```mbt check
///|
test {
  // A get_peers query, as a node would send it.
  let query = @moonbit-bencode.Value::dict_of([
    (b"t", @moonbit-bencode.Value::str(b"aa")),
    (b"y", @moonbit-bencode.Value::str(b"q")),
    (b"q", @moonbit-bencode.Value::str(b"get_peers")),
    (
      b"a",
      @moonbit-bencode.Value::dict_of([
        (b"id", @moonbit-bencode.Value::str(b"abcdefghij0123456789")),
        (b"info_hash", @moonbit-bencode.Value::str(b"mnopqrstuvwxyz123456")),
      ]),
    ),
  ])
  let wire = @moonbit-bencode.encode(query)
  // The socket delivers it in fragments: the first slice is still incomplete,
  // so try_next returns None and the decoder keeps the bytes buffered.
  let dec = @moonbit-bencode.StreamDecoder::StreamDecoder()
  dec.feed(wire[:20])
  assert_true(dec.try_next() is None)
  assert_true(dec.pending() > 0)
  dec.feed(wire[20:])
  let message = dec.try_next().unwrap()
  assert_eq(message.get_path([b"y"]).unwrap().as_str().unwrap(), b"q")
  assert_eq(message.get_path([b"q"]).unwrap().as_str().unwrap(), b"get_peers")
  // The 20-byte info hash is binary: never treat it as text.
  let info_hash = message
    .get_path([b"a", b"info_hash"])
    .unwrap()
    .as_str()
    .unwrap()
  assert_eq(info_hash.length(), 20)
  assert_eq(dec.pending(), 0)
}
```

The same decoder handles several messages arriving in one datagram: call
`try_next` until it returns `None` again, then wait for the next packet.
`pending()` tells you whether the buffer is empty — at a clean message
boundary it is zero.

### Integers without a width limit

BEP 3 does not bound integer size, so neither does the decoder: anything that
fits stays in `Int64`, and larger magnitudes become `BigInt` instead of an
error. Reading back is a choice, not a guess.

```mbt check
///|
test {
  // 2^64 + 1 does not fit in 64 bits.
  let value = @moonbit-bencode.decode(b"i18446744073709551617e")
  assert_true(value.as_int() is None)
  let big = value.as_bigint().unwrap()
  assert_eq(big.to_string(), "18446744073709551617")
  // Encoding writes the same literal back.
  assert_eq(@moonbit-bencode.encode(value), b"i18446744073709551617e")
  // A value that happens to fit can still be read as an Int64.
  let small = @moonbit-bencode.decode(b"i42e")
  assert_eq(small.as_integer().unwrap().to_int64(), Some(42L))
}
```

### Tracker announce responses

`AnnounceResponse::parse` turns a decoded response into typed fields and
handles both peer encodings — the compact BEP 23 form and the older list of
dictionaries:

```mbt check
///|
test {
  let wire = @moonbit-bencode.Value::dict_of([
    (b"interval", @moonbit-bencode.Value::int(1800L)),
    (b"complete", @moonbit-bencode.Value::int(12L)),
    // 127.0.0.1:6881 in compact form: four address bytes, then the port.
    (b"peers", @moonbit-bencode.Value::str(b"\x7f\x00\x00\x01\x1a\xe1")),
  ])
  let response = @moonbit-bencode.AnnounceResponse::parse(wire)
  assert_eq(response.interval(), Some(1800L))
  assert_eq(response.complete(), Some(12L))
  let peers = response.peers()
  assert_eq(peers.length(), 1)
  assert_eq(peers[0].ip_string(), "127.0.0.1")
  assert_eq(peers[0].port(), (6881 : UInt16))
  // The raw address stays binary: four bytes, never text.
  assert_eq(peers[0].ip().length(), 4)
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
| `AnnounceResponse::parse(value)` | typed tracker response |
| `Peer::{ip, port, ip_string}` | peer address, binary first |
| `BigInt::{parse, to_int64, from_int64}` | arbitrary-precision integers |
| `Value::{as_int, as_integer, as_bigint}` | integer accessors |
| `DecodeError` / `TrackerError` | `suberror`s with byte offsets |

## Development

```sh
moon test             # 75 tests: spec vectors, malformed input, streams, property
moon test README.mbt.md  # run just the README examples (7 doctests)
moon fmt && moon info
moon bench --release  # throughput numbers for decode/encode/streaming
```

## Benchmarks

`moon bench --release`, release build on one Windows x86_64 machine — treat as
ballpark, not a promise. Payload: a metainfo dictionary whose `pieces` field is
20 KiB (1000 × 20-byte hashes), i.e. a realistic torrent.

| Benchmark | Mean |
| --- | --- |
| decode metainfo | 3.19 µs |
| encode metainfo | 2.82 µs |
| roundtrip (decode then encode) | 5.67 µs |
| streaming decode, 1 KiB chunks | 36.6 µs |

Supporting unbounded integers cost about 25 % on decode: `Value` gained a
fifth variant, so the enum got larger and every value move pays for it.
That is the price of not rejecting data the format allows, and it is
recorded here rather than hidden — see issue #8.

Streaming is slower than one-shot decoding because every `try_next` retries the
parse from the last value boundary, so the cost grows with the number of
chunks. For DHT-sized messages (a few hundred bytes) that difference is noise;
for a whole file, use the one-shot `decode`.

## References

- [BEP 3: The BitTorrent Protocol Specification](https://www.bittorrent.org/beps/bep_0003.html)
  — the bencode grammar, canonical rules and the metainfo structure.
- [BEP 5: DHT Protocol](https://www.bittorrent.org/beps/bep_0005.html)
  — stream-oriented peer messages, the streaming use case.
- Implementations consulted for behaviour (not code): `bencode` for Python,
  `serde_bencode` for Rust, `bencode-go`.

## License

Apache-2.0
