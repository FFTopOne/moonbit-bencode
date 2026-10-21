///|
/// # moonbit-bencode
///
/// A spec-complete codec for [bencode](https://www.bittorrent.org/beps/bep_0003.html),
/// the encoding used by BitTorrent `.torrent` files, tracker traffic and the
/// DHT protocol.
///
/// ## Design goals
///
/// - **Strict decoding**: malformed integers, bad length prefixes and
///   truncated payloads are rejected with the byte offset of the problem.
/// - **Canonical encoding**: keys are always emitted in sorted order, so
///   re-encoding a decoded value reproduces a canonical payload byte for
///   byte.
/// - **Streaming**: `StreamDecoder` decodes values incrementally from a
///   sequence of chunks, which is what network protocols need.
/// - **Zero dependencies**: the library only uses `moonbitlang/core`.
///
/// ## Integer range
///
/// Bencode integers are unbounded in the spec. This implementation stores
/// them as signed 64-bit values and rejects literals outside that range
/// with `IntegerOverflow`. Real-world payloads stay far below the bound.

///|
/// Decode a complete bencoded payload.
///
/// Raises `DecodeError` when the input is malformed or when trailing bytes
/// follow the first complete value. Use `StreamDecoder` when the payload
/// boundary is not known in advance.
pub fn decode(data : Bytes) -> Value raise DecodeError {
  guard !data.is_empty() else { raise UnexpectedEnd(0) }
  let cursor = Cursor::{ view: data[:], pos: 0, depth: 0, }
  let value = cursor.decode_value()
  guard cursor.pos == data.length() else {
    raise TrailingData(data.length() - cursor.pos)
  }
  value
}

///|
/// Encode a value into canonical bencode form and return fresh `Bytes`.
pub fn encode(value : Value) -> Bytes {
  let buf = Buffer()
  encode_into(buf, value)
  buf.contents()
}

///|
/// Try to decode exactly one value from the front of `view`.
///
/// Returns `None` when the view ends in the middle of a value, which lets
/// streaming callers ask for more input. Malformed data still raises.
fn decode_stream_value(view : BytesView) -> (Value, Int32)? raise DecodeError {
  let cursor = Cursor::{ view, pos: 0, depth: 0, }
  let value : Value? = Some(cursor.decode_value()) catch {
    UnexpectedEnd(_) => None
    e => raise e
  }
  match value {
    None => None
    Some(v) => Some((v, cursor.pos))
  }
}

///|
/// Incremental decoder for bencoded streams, e.g. the BitTorrent DHT
/// protocol where several values arrive back-to-back on one socket.
///
/// Feed chunks with `feed` and pull complete values with `try_next`.
pub struct StreamDecoder {
  mut buf : Buffer
  mut consumed : Int32
}

///|
/// Create an empty stream decoder.
pub fn StreamDecoder::StreamDecoder() -> StreamDecoder {
  { buf: Buffer(), consumed: 0, }
}

///|
/// Append a chunk of bytes to the internal buffer.
pub fn StreamDecoder::feed(self : StreamDecoder, chunk : BytesView) -> Unit {
  self.buf.write_bytes(chunk)
}

///|
/// Decode the next complete value, or `None` when more input is needed.
///
/// Raises `DecodeError` as soon as the buffered bytes are definitely
/// malformed. Note that a truncated tail is indistinguishable from a
/// stream that has simply not delivered the rest of the value yet; both
/// yield `None`.
pub fn StreamDecoder::try_next(
  self : StreamDecoder,
) -> Value? raise DecodeError {
  let data = self.buf.contents()
  let pending = data[self.consumed:]
  match decode_stream_value(pending) {
    None => None
    Some((value, n)) => {
      self.consumed += n
      self.compact()
      Some(value)
    }
  }
}

///|
/// Number of buffered bytes that have not been decoded yet. When this is
/// zero and `try_next` returns `None`, the stream is at a clean boundary.
pub fn StreamDecoder::pending(self : StreamDecoder) -> Int32 {
  self.buf.length() - self.consumed
}

///|
/// Drop everything buffered so far, e.g. after a protocol error.
pub fn StreamDecoder::clear(self : StreamDecoder) -> Unit {
  self.buf = Buffer()
  self.consumed = 0
}

///|
/// Drop the already-decoded prefix once it grows large, so that long
/// streams do not buffer the whole history.
fn StreamDecoder::compact(self : StreamDecoder) -> Unit {
  if self.consumed >= 4096 {
    let data = self.buf.contents()
    let rest = data[self.consumed:]
    let buf = Buffer()
    buf.write_bytes(rest)
    self.buf = buf
    self.consumed = 0
  }
}
