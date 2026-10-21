///|
/// Error raised when decoding malformed bencoded data.
///
/// Every variant records the byte offset where the problem was detected, so
/// callers can point users at the exact location inside a `.torrent` file, a
/// DHT message, or any other bencoded payload.
pub suberror DecodeError {
  /// The input ended in the middle of a value at byte `pos`.
  UnexpectedEnd(Int32)
  /// The byte `b` at `pos` cannot start or continue a value.
  UnexpectedByte(Byte, Int32)
  /// A malformed integer literal starts at byte `pos`.
  InvalidInteger(Int32)
  /// A malformed byte-string length prefix starts at byte `pos`.
  InvalidLength(Int32)
  /// The integer literal at `pos` does not fit in a signed 64-bit integer.
  IntegerOverflow(Int32)
  /// The dictionary key at `pos` is not a byte string.
  InvalidDictKey(Int32)
  /// `count` trailing bytes follow the first complete top-level value.
  TrailingData(Int32)
}

///|
/// Human-readable description of a decoding failure.
pub impl Show for DecodeError with fn output(self, logger) {
  logger.write_string(
    match self {
      UnexpectedEnd(pos) => "unexpected end of input at byte \{pos}"
      UnexpectedByte(b, pos) => "unexpected byte 0x\{b.to_hex()} at byte \{pos}"
      InvalidInteger(pos) => "malformed integer literal at byte \{pos}"
      InvalidLength(pos) => "malformed byte-string length at byte \{pos}"
      IntegerOverflow(pos) =>
        "integer at byte \{pos} overflows the signed 64-bit range"
      InvalidDictKey(pos) =>
        "dictionary key at byte \{pos} is not a byte string"
      TrailingData(count) =>
        "\{count} trailing byte(s) after the top-level value"
    },
  )
}

///|
pub extend DecodeError with Show::{output, to_string}
