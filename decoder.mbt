///|
/// Largest bencode integer magnitude: a signed 64-bit value.
///
/// Bencode integers are unbounded in the spec, but every real-world payload
/// (`.torrent` metainfo, DHT messages, ...) stays far below this bound.
/// Magnitudes are folded as `UInt64` so that the negative extreme `-2^63`
/// stays reachable: `+2^63` itself does not fit in `Int64`.
const UINT64_MAX_I64 : UInt64 = 9223372036854775807UL

///|
const UINT64_MIN_MAGNITUDE : UInt64 = 9223372036854775808UL

///|
/// Longest byte string we can address on this platform. `Bytes::length` is
/// a 32-bit integer, so a longer string could never be materialised anyway.
const MAX_STRING_LENGTH : Int64 = 2147483647L

///|
/// Maximum container nesting depth.
///
/// Decoding is recursive, so an adversarial payload such as
/// `l` repeated a million times would otherwise exhaust the stack and take
/// the process down without a catchable error. Real payloads nest a handful
/// of levels at most; 512 is far above anything legitimate while keeping the
/// recursion safely bounded.
const MAX_NESTING_DEPTH : Int32 = 512

///|
/// Maximum container nesting depth the decoder accepts.
///
/// Payloads nested deeper are rejected with `NestingTooDeep` instead of
/// risking a stack overflow.
pub fn max_nesting_depth() -> Int32 {
  MAX_NESTING_DEPTH
}

///|
/// A read cursor over a byte view. All positions are 0-based byte offsets.
priv struct Cursor {
  view : BytesView
  mut pos : Int32
  mut depth : Int32
}

///|
/// Byte at the cursor, or `None` at the end of the view.
fn Cursor::peek(self : Cursor) -> Byte? {
  self.view.get(self.pos)
}

///|
/// Consume one byte; raises `UnexpectedEnd` at the end of the view.
fn Cursor::read_byte(self : Cursor) -> Byte raise DecodeError {
  match self.view.get(self.pos) {
    Some(b) => {
      self.pos += 1
      b
    }
    None => raise UnexpectedEnd(self.pos)
  }
}

///|
/// Consume one byte and require it to be `expected`.
fn Cursor::expect(self : Cursor, expected : Byte) -> Unit raise DecodeError {
  let b = self.read_byte()
  if b != expected {
    raise UnexpectedByte(b, self.pos - 1)
  }
}

///|
fn is_ascii_digit(b : Byte) -> Bool {
  b >= b'0' && b <= b'9'
}

///|
/// Decode one value starting at the cursor. The cursor is left just past the
/// value, so the caller can learn how many bytes were consumed.
fn Cursor::decode_value(self : Cursor) -> Value raise DecodeError {
  let b = self.read_byte()
  if b == b'i' {
    self.decode_int_body()
  } else if b == b'l' {
    self.decode_list_body()
  } else if b == b'd' {
    self.decode_dict_body()
  } else if is_ascii_digit(b) {
    // Rewind so the length prefix is read from its first digit.
    self.pos -= 1
    self.decode_str_body()
  } else {
    raise UnexpectedByte(b, self.pos - 1)
  }
}

///|
/// Decode `i<int>e`. The leading `i` has already been consumed.
fn Cursor::decode_int_body(self : Cursor) -> Value raise DecodeError {
  let start = self.pos
  let negative = match self.peek() {
    Some(b'-') => {
      self.pos += 1
      true
    }
    _ => false
  }
  let digits_start = self.pos
  self.skip_digits()
  let digits_end = self.pos
  let ndigits = digits_end - digits_start
  // No digits yet: at the end of the view this is a truncated value (a
  // stream may still deliver more), otherwise it is definitely malformed.
  guard ndigits > 0 else {
    if self.peek() is None {
      raise UnexpectedEnd(self.pos)
    } else {
      raise InvalidInteger(start)
    }
  }
  // "0", "-0", "007" and friends are not valid bencode integers.
  guard !(ndigits > 1 && self.view.at(digits_start) == b'0') else {
    raise InvalidInteger(start)
  }
  guard !(negative && self.view.at(digits_start) == b'0') else {
    raise InvalidInteger(start)
  }
  self.expect(b'e')
  let limit = if negative { UINT64_MIN_MAGNITUDE } else { UINT64_MAX_I64 }
  let mut magnitude : UInt64 = 0
  for i in digits_start..<digits_end {
    let digit = (self.view.at(i) - b'0').to_uint64()
    guard magnitude <= (limit - digit) / 10 else {
      raise IntegerOverflow(start)
    }
    magnitude = magnitude * 10 + digit
  }
  // Negating in unsigned arithmetic and reinterpreting keeps `-2^63`
  // exact: `0 - 2^63` wraps to `2^63`, which reads back as `Int64` min.
  Int(
    if negative {
      (0UL - magnitude).reinterpret_as_int64()
    } else {
      magnitude.reinterpret_as_int64()
    },
  )
}

///|
/// Decode `<len>:<bytes>`. The cursor sits on the first length digit.
fn Cursor::decode_str_body(self : Cursor) -> Value raise DecodeError {
  let start = self.pos
  self.skip_digits()
  let digits_end = self.pos
  let ndigits = digits_end - start
  guard ndigits > 0 else { raise InvalidLength(start) }
  // A length prefix never has leading zeros ("05:" is malformed).
  guard !(ndigits > 1 && self.view.at(start) == b'0') else {
    raise InvalidLength(start)
  }
  self.expect(b':')
  let mut length : Int64 = 0
  for i in start..<digits_end {
    let digit = (self.view.at(i) - b'0').to_int().to_int64()
    guard length <= (MAX_STRING_LENGTH - digit) / 10 else {
      raise InvalidLength(start)
    }
    length = length * 10 + digit
  }
  let len = length.to_int()
  let end = self.pos + len
  guard end <= self.view.length() else { raise UnexpectedEnd(start) }
  let s = self.view[self.pos:end].to_owned()
  self.pos = end
  Str(s)
}

///|
/// Decode `l<items>e`. The leading `l` has already been consumed.
fn Cursor::decode_list_body(self : Cursor) -> Value raise DecodeError {
  let open_pos = self.pos - 1
  self.depth += 1
  guard self.depth <= MAX_NESTING_DEPTH else { raise NestingTooDeep(open_pos) }
  let items : Array[Value] = []
  while true {
    match self.peek() {
      Some(b'e') => {
        self.pos += 1
        break
      }
      None => raise UnexpectedEnd(self.pos)
      _ => items.push(self.decode_value())
    }
  }
  self.depth -= 1
  List(items)
}

///|
/// Decode `d<pairs>e`. The leading `d` has already been consumed.
///
/// Key order is *not* enforced: real-world payloads are occasionally
/// non-canonical, and the encoder always re-emits keys in sorted order.
fn Cursor::decode_dict_body(self : Cursor) -> Value raise DecodeError {
  let open_pos = self.pos - 1
  self.depth += 1
  guard self.depth <= MAX_NESTING_DEPTH else { raise NestingTooDeep(open_pos) }
  let pairs : Array[(Bytes, Value)] = []
  while true {
    match self.peek() {
      Some(b'e') => {
        self.pos += 1
        break
      }
      None => raise UnexpectedEnd(self.pos)
      _ => {
        let key_pos = self.pos
        let key = match self.decode_value() {
          Str(s) => s
          _ => raise InvalidDictKey(key_pos)
        }
        let value = self.decode_value()
        pairs.push((key, value))
      }
    }
  }
  self.depth -= 1
  Dict(Map::Map(pairs[:]))
}

///|
fn Cursor::skip_digits(self : Cursor) -> Unit {
  while true {
    match self.peek() {
      Some(d) if is_ascii_digit(d) => self.pos += 1
      _ => break
    }
  }
}
