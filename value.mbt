///|
/// A decoded bencode value.
///
/// Bencode (BEP 3) has exactly four types, and `Value` mirrors them one-to-one:
///
/// - `Int` holds a signed 64-bit integer,
/// - `Str` holds an owned copy of a byte string. Bencode strings are
///   binary-safe: they are *not* guaranteed to be valid UTF-8,
/// - `List` holds the elements in encoded order,
/// - `Dict` maps byte-string keys to values. Keys keep their first-insertion
///   order; when the same key appears more than once the last value wins.
///
/// Values are compared structurally with `==`.
pub enum Value {
  Int(Int64)
  /// An integer literal that does not fit in `Int64`. BEP 3 puts no bound on
  /// integer size, so these are represented instead of rejected.
  BigInt(BigInt)
  Str(Bytes)
  List(Array[Value])
  Dict(Map[Bytes, Value])
}

///|
/// Build an integer value.
pub fn Value::int(v : Int64) -> Value {
  Int(v)
}

///|
/// Build an arbitrary-precision integer value.
pub fn Value::big_int(v : BigInt) -> Value {
  BigInt(v)
}

///|
/// Build a byte-string value.
pub fn Value::str(v : Bytes) -> Value {
  Str(v)
}

///|
/// Build a list value from its elements.
pub fn Value::list(items : Array[Value]) -> Value {
  List(items)
}

///|
/// Build an empty dictionary value.
pub fn Value::dict() -> Value {
  Dict(Map::Map([]))
}

///|
/// Build a dictionary value from key/value pairs. When a key appears more
/// than once, the last value wins and the key keeps its first position.
pub fn Value::dict_of(pairs : Array[(Bytes, Value)]) -> Value {
  Dict(Map::Map(pairs[:]))
}

///|
/// Return the integer payload, or `None` for the other variants.
pub fn Value::as_int(self : Value) -> Int64? {
  match self {
    Int(v) => Some(v)
    _ => None
  }
}

///|
/// Return the arbitrary-precision payload, or `None` for the other variants.
pub fn Value::as_bigint(self : Value) -> BigInt? {
  match self {
    BigInt(v) => Some(v)
    _ => None
  }
}

///|
/// Return the integer payload of either representation: `Int` directly, and
/// `BigInt` when it happens to fit in 64 bits.
pub fn Value::as_integer(self : Value) -> BigInt? {
  match self {
    Int(v) => Some(BigInt::from_int64(v))
    BigInt(v) => Some(v)
    _ => None
  }
}

///|
/// Return the byte-string payload, or `None` for the other variants.
pub fn Value::as_str(self : Value) -> Bytes? {
  match self {
    Str(s) => Some(s)
    _ => None
  }
}

///|
/// Return the list payload (a live, mutable array), or `None`.
pub fn Value::as_list(self : Value) -> Array[Value]? {
  match self {
    List(items) => Some(items)
    _ => None
  }
}

///|
/// Return the dictionary payload (a live, mutable map), or `None`.
pub fn Value::as_dict(self : Value) -> Map[Bytes, Value]? {
  match self {
    Dict(m) => Some(m)
    _ => None
  }
}

///|
/// Look up `key` in a dictionary value. Returns `None` when `self` is not a
/// dictionary or the key is absent.
pub fn Value::get(self : Value, key : Bytes) -> Value? {
  match self {
    Dict(m) => m.get(key)
    _ => None
  }
}

///|
/// Follow a chain of dictionary keys, e.g.
/// `value.get_path([b"info", b"length"])` inside a `.torrent` metainfo.
/// Returns `None` as soon as one step is missing or not a dictionary.
pub fn Value::get_path(self : Value, keys : Array[Bytes]) -> Value? {
  let mut current : Value? = Some(self)
  for key in keys {
    current = match current {
      Some(v) => v.get(key)
      None => None
    }
  }
  current
}

///|
/// Structural equality: two values are equal when they have the same shape
/// and the same payloads. Dictionary comparison ignores key order.
pub impl Eq for Value with fn equal(self, other) {
  match (self, other) {
    (Int(a), Int(b)) => a == b
    (Int(a), BigInt(b)) => BigInt::from_int64(a) == b
    (BigInt(a), Int(b)) => a == BigInt::from_int64(b)
    (BigInt(a), BigInt(b)) => a == b
    (Str(a), Str(b)) => a == b
    (List(a), List(b)) => array_equal(a, b)
    (Dict(a), Dict(b)) => map_equal(a, b)
    _ => false
  }
}

///|
pub extend Value with Eq::{equal, not_equal}

///|
fn array_equal(a : Array[Value], b : Array[Value]) -> Bool {
  if a.length() != b.length() {
    false
  } else {
    let mut equal = true
    for i in 0..<a.length() {
      if !(a[i] == b[i]) {
        equal = false
      }
    }
    equal
  }
}

///|
fn map_equal(a : Map[Bytes, Value], b : Map[Bytes, Value]) -> Bool {
  if a.length() != b.length() {
    false
  } else {
    let mut equal = true
    for (k, v) in a {
      match b.get(k) {
        Some(other) => if !(v == other) { equal = false }
        None => equal = false
      }
    }
    equal
  }
}

///|
/// Compact, single-line rendering used by the CLI and in test snapshots.
///
/// Byte strings are shown quoted, with non-printable bytes escaped as `\xNN`;
/// they are *not* assumed to be UTF-8.
pub impl Show for Value with fn output(self, logger) {
  self.write_compact(logger)
}

///|
pub extend Value with Show::{output, to_string}

///|
/// Structured debug rendering. Byte strings are shown through the same
/// escaping as `Show`, so binary payloads stay readable.
pub impl Debug for Value with fn to_repr(self) {
  match self {
    Int(v) => Repr::ctor("Int", [(None, Repr::integer(v.to_string()))])
    BigInt(v) => Repr::ctor("BigInt", [(None, Repr::integer(v.to_string()))])
    Str(s) => Repr::ctor("Str", [(None, Repr::literal(quote_bytes(s)))])
    List(items) => {
      let children : Array[Repr] = []
      for item in items {
        children.push(item.to_repr())
      }
      Repr::ctor("List", [(None, Repr::array(children))])
    }
    Dict(m) => {
      let entries : Array[(Repr, Repr)] = []
      for (k, v) in m {
        entries.push((Repr::literal(quote_bytes(k)), v.to_repr()))
      }
      Repr::ctor("Dict", [(None, Repr::map(entries))])
    }
  }
}

///|
pub extend Value with Debug::{to_repr}

///|
fn Value::write_compact(self : Value, logger : &Logger) -> Unit {
  match self {
    Int(v) => logger.write_string(v.to_string())
    BigInt(v) => logger.write_string(v.to_string())
    Str(s) => logger.write_string(quote_bytes(s))
    List(items) => {
      logger.write_char('[')
      let mut first = true
      for item in items {
        if first {
          first = false
        } else {
          logger.write_string(", ")
        }
        item.write_compact(logger)
      }
      logger.write_char(']')
    }
    Dict(m) => {
      logger.write_char('{')
      let mut first = true
      for (k, v) in m {
        if first {
          first = false
        } else {
          logger.write_string(", ")
        }
        logger.write_string(quote_bytes(k))
        logger.write_string(": ")
        v.write_compact(logger)
      }
      logger.write_char('}')
    }
  }
}

///|
/// Render a byte string as a quoted literal, escaping quotes, backslashes
/// and every non-printable byte as `\xNN`.
fn quote_bytes(s : Bytes) -> String {
  let logger = StringBuilder()
  logger.write_char('"')
  for b in s {
    if b == b'"' {
      logger.write_string("\\\"")
    } else if b == b'\\' {
      logger.write_string("\\\\")
    } else if b >= b' ' && b <= b'~' {
      match b.to_int().to_char() {
        Some(c) => logger.write_char(c)
        None => {
          logger.write_string("\\x")
          logger.write_string(b.to_hex())
        }
      }
    } else {
      logger.write_string("\\x")
      logger.write_string(b.to_hex())
    }
  }
  logger.write_char('"')
  logger.to_string()
}
