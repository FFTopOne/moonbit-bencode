///|
/// Benchmarks for the hot paths: one-shot decode, canonical encode and
/// chunked streaming decode.
///
/// Run with `moon bench --release`. The payload mirrors a real `.torrent`
/// metainfo, dominated by a 20 KiB `pieces` byte string (1000 × 20-byte
/// SHA-1 hashes).

///|
/// Decode or die — benchmark closures may not raise.
fn decode_or_panic(data : Bytes) -> @moonbit-bencode.Value {
  @moonbit-bencode.decode(data) catch {
    e => {
      println("bench decode failed: \{e}")
      panic()
    }
  }
}

///|
/// Build a metainfo payload that looks like a real torrent file.
fn sample_metainfo() -> Bytes {
  let pieces = Bytes::make(20_000, b'\x5a')
  let info = @moonbit-bencode.Value::dict_of([
    (b"name", @moonbit-bencode.Value::str(b"ubuntu-24.04-desktop-amd64.iso")),
    (b"length", @moonbit-bencode.Value::int(5_368_709_120L)),
    (b"piece length", @moonbit-bencode.Value::int(262_144L)),
    (b"pieces", @moonbit-bencode.Value::str(pieces)),
  ])
  let metainfo = @moonbit-bencode.Value::dict_of([
    (
      b"announce",
      @moonbit-bencode.Value::str(b"http://tracker.example.com/announce"),
    ),
    (b"info", info),
  ])
  @moonbit-bencode.encode(metainfo)
}

///|
test "bench decode metainfo" (it : @bench.T) {
  let data = sample_metainfo()
  it.bench(fn() { it.keep(decode_or_panic(data)) })
}

///|
test "bench encode metainfo" (it : @bench.T) {
  let value = decode_or_panic(sample_metainfo())
  it.bench(fn() { it.keep(@moonbit-bencode.encode(value)) })
}

///|
test "bench roundtrip metainfo" (it : @bench.T) {
  let data = sample_metainfo()
  it.bench(fn() { it.keep(@moonbit-bencode.encode(decode_or_panic(data))) })
}

///|
test "bench streaming decode in 1 KiB chunks" (it : @bench.T) {
  let data = sample_metainfo()
  it.bench(fn() {
    let dec = @moonbit-bencode.StreamDecoder::StreamDecoder()
    let mut i = 0
    while i < data.length() {
      let end = if i + 1024 < data.length() { i + 1024 } else { data.length() }
      dec.feed(data[i:end])
      let _ = dec.try_next() catch {
        e => {
          println("bench stream failed: \{e}")
          panic()
        }
      }
      i = end
    }
    it.keep(dec.pending())
  })
}
