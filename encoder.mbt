///|
/// Encode `value` into `buf` in canonical bencode form.
///
/// Canonical means: integers use the shortest possible form (no leading
/// zeros, no minus zero), and dictionary keys are emitted in ascending
/// byte-string order — the form mandated by BEP 3 for `.torrent` files.
pub fn encode_into(buf : Buffer, value : Value) -> Unit {
  match value {
    Int(n) => {
      buf.write_byte(b'i')
      buf.write_string_utf8(n.to_string())
      buf.write_byte(b'e')
    }
    BigInt(n) => {
      buf.write_byte(b'i')
      if n.is_negative() {
        buf.write_byte(b'-')
      }
      for d in n.digits() {
        buf.write_byte(d)
      }
      buf.write_byte(b'e')
    }
    Str(s) => {
      buf.write_string_utf8(s.length().to_string())
      buf.write_byte(b':')
      buf.write_bytes(s)
    }
    List(items) => {
      buf.write_byte(b'l')
      for item in items {
        encode_into(buf, item)
      }
      buf.write_byte(b'e')
    }
    Dict(m) => {
      buf.write_byte(b'd')
      let pairs = m.to_array()
      // BEP 3 requires raw byte-string order, which is *not* the same as
      // `Compare` for `Bytes` (that one orders by length first).
      pairs.sort_by(fn(a, b) { a.0.lexical_compare(b.0) })
      for pair in pairs {
        let key = pair.0
        buf.write_string_utf8(key.length().to_string())
        buf.write_byte(b':')
        buf.write_bytes(key)
        encode_into(buf, pair.1)
      }
      buf.write_byte(b'e')
    }
  }
}
