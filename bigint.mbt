///|
/// An arbitrary-precision bencode integer.
///
/// BEP 3 places no bound on the size of an integer literal, so a codec that
/// claims to implement the format completely must be able to hold values
/// beyond any fixed width. `BigInt` stores the sign plus normalised decimal
/// digits, which is exactly what bencode literals look like — no conversion
/// to binary limbs is needed to parse or re-emit them, so there is no
/// precision loss anywhere in the round trip.
///
/// Values that fit in `Int64` still decode into `Value::Int`, which is the
/// cheap representation; only genuinely large magnitudes reach `BigInt`.

///|
/// Sign plus base-10 digits, most significant first, no leading zeros.
///
/// The zero value is `{ negative: false, digits: [0] }`; `-0` is not
/// representable, matching bencode's canonical form.
pub struct BigInt {
  negative : Bool
  digits : Array[Byte]
}

///|
/// Build a big integer from a sign and decimal digits.
///
/// The digits are normalised: leading zeros are dropped and an all-zero
/// magnitude becomes a non-negative zero. Callers are responsible for
/// passing ASCII digits; use `BigInt::make` to validate untrusted input.
pub fn BigInt::BigInt(negative : Bool, digits : Array[Byte]) -> BigInt {
  let normalised : Array[Byte] = []
  let mut leading = true
  for d in digits {
    if d == b'0' && leading {
      continue
    }
    leading = false
    normalised.push(d)
  }
  if normalised.is_empty() {
    { negative: false, digits: [b'0'], }
  } else {
    { negative, digits: normalised, }
  }
}

///|
/// Validate and build a big integer. Returns `None` when `digits` is empty
/// or contains anything other than ASCII digits.
pub fn BigInt::make(negative : Bool, digits : Array[Byte]) -> BigInt? {
  guard !digits.is_empty() else { return None }
  for d in digits {
    guard d >= b'0' && d <= b'9' else { return None }
  }
  Some(BigInt::BigInt(negative, digits))
}

///|
/// The sign: `true` when the value is negative. Zero is never negative.
pub fn BigInt::is_negative(self : BigInt) -> Bool {
  self.negative
}

///|
/// The decimal digits without any sign, most significant first. The
/// representation has no leading zeros, so zero is the single digit `0`.
pub fn BigInt::digits(self : BigInt) -> Array[Byte] {
  self.digits
}

///|
/// Convert to a signed 64-bit integer, or `None` when the value does not
/// fit. Round trips exactly for every in-range value.
pub fn BigInt::to_int64(self : BigInt) -> Int64? {
  let mut magnitude : UInt64 = 0
  let limit : UInt64 = if self.negative {
    9223372036854775808UL
  } else {
    9223372036854775807UL
  }
  for d in self.digits {
    let digit = (d - b'0').to_uint64()
    guard magnitude <= (limit - digit) / 10 else { return None }
    magnitude = magnitude * 10 + digit
  }
  Some(
    if self.negative {
      (0UL - magnitude).reinterpret_as_int64()
    } else {
      magnitude.reinterpret_as_int64()
    },
  )
}

///|
/// Build from a signed 64-bit integer.
pub fn BigInt::from_int64(value : Int64) -> BigInt {
  let negative = value < 0L
  let bits = value.reinterpret_as_uint64()
  let magnitude : UInt64 = if negative { 0UL - bits } else { bits }
  let text = magnitude.to_string()
  let digits : Array[Byte] = []
  for i in 0..<text.length() {
    digits.push(text[i].to_byte())
  }
  match BigInt::make(negative, digits) {
    Some(b) => b
    None => panic()
  }
}

///|
/// Parse a canonical decimal literal (`-12345`, `0`, `999…`).
///
/// Leading zeros, a bare `-`, and non-digit bytes are rejected; a leading
/// `-` followed only by zeros is rejected too, because `-0` is not a
/// canonical bencode integer.
pub fn BigInt::parse(bytes : Bytes) -> BigInt? {
  guard !bytes.is_empty() else { return None }
  let negative = bytes[0] == b'-'
  let body = if negative { bytes[1:] } else { bytes }
  guard !body.is_empty() else { return None }
  for b in body {
    guard b >= b'0' && b <= b'9' else { return None }
  }
  // Canonical literals carry no leading zeros, and "-0" is not a value.
  guard body.length() == 1 || body[0] != b'0' else { return None }
  guard !(negative && body.length() == 1 && body[0] == b'0') else {
    return None
  }
  let arr : Array[Byte] = []
  for i in 0..<body.length() {
    arr.push(body[i])
  }
  BigInt::make(negative, arr)
}

///|
/// The decimal literal, including a leading `-` for negative values.
///
/// Exposed as `to_string` through the `Show` instance below.
fn BigInt::render(self : BigInt) -> String {
  let sb = StringBuilder()
  if self.negative {
    sb.write_char('-')
  }
  for d in self.digits {
    match d.to_int().to_char() {
      Some(c) => sb.write_char(c)
      None => panic()
    }
  }
  sb.to_string()
}

///|
/// Structural equality. `BigInt::from_int64(5) == BigInt::BigInt(false, [b'5'])`.
pub impl Eq for BigInt with fn equal(self, other) {
  if self.negative != other.negative {
    false
  } else if self.digits.length() != other.digits.length() {
    false
  } else {
    let mut equal = true
    for i in 0..<self.digits.length() {
      if self.digits[i] != other.digits[i] {
        equal = false
      }
    }
    equal
  }
}

///|
pub extend BigInt with Eq::{equal, not_equal}

///|
pub impl Show for BigInt with fn output(self, logger) {
  logger.write_string(self.render())
}

///|
pub extend BigInt with Show::{output, to_string}
