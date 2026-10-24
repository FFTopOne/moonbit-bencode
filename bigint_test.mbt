///|
/// Tests for arbitrary-precision integers — the part of BEP 3 that a fixed
/// width representation cannot cover.

///|
fn digits_of(text : Bytes) -> Array[Byte] {
  let arr : Array[Byte] = []
  for i in 0..<text.length() {
    arr.push(text[i])
  }
  arr
}

///|
test "parse and render round-trip" {
  let cases : Array[(Bytes, String)] = [
    (b"0", "0"),
    (b"7", "7"),
    (b"-7", "-7"),
    (b"9223372036854775807", "9223372036854775807"),
    (b"-9223372036854775808", "-9223372036854775808"),
    (b"9223372036854775808", "9223372036854775808"),
    (b"99999999999999999999999999999999", "99999999999999999999999999999999"),
  ]
  for (literal, expected) in cases {
    let big = @moonbit-bencode.BigInt::parse(literal).unwrap()
    assert_eq(big.to_string(), expected)
    assert_eq(big.is_negative(), literal[0] == b'-')
  }
}

///|
test "parse rejects non-canonical literals" {
  let bad = [
    b"", b"-", b"-0", b"00", b"01", b"-01", b"1a", b" 1", b"1 ", b"+1", b"--1",
  ]
  for literal in bad {
    assert_true(@moonbit-bencode.BigInt::parse(literal) is None)
  }
}

///|
test "construction normalises digits" {
  let big = @moonbit-bencode.BigInt::BigInt(false, digits_of(b"007"))
  assert_eq(big.to_string(), "7")
  let zero = @moonbit-bencode.BigInt::BigInt(true, digits_of(b"000"))
  assert_eq(zero.to_string(), "0")
  assert_true(!zero.is_negative())
  // make() rejects anything that is not a digit.
  assert_true(@moonbit-bencode.BigInt::make(false, []) is None)
  assert_true(@moonbit-bencode.BigInt::make(false, digits_of(b"1x")) is None)
}

///|
test "to_int64 reports the representable range exactly" {
  let max = @moonbit-bencode.BigInt::parse(b"9223372036854775807").unwrap()
  assert_eq(max.to_int64(), Some(9223372036854775807L))
  let min = @moonbit-bencode.BigInt::parse(b"-9223372036854775808").unwrap()
  assert_eq(min.to_int64(), Some(-9223372036854775808L))
  let over = @moonbit-bencode.BigInt::parse(b"9223372036854775808").unwrap()
  assert_true(over.to_int64() is None)
  let under = @moonbit-bencode.BigInt::parse(b"-9223372036854775809").unwrap()
  assert_true(under.to_int64() is None)
}

///|
test "from_int64 round-trips every boundary" {
  let values = [
    0L, 1L, -1L, 42L, -42L, 9223372036854775807L, -9223372036854775808L,
  ]
  for v in values {
    let big = @moonbit-bencode.BigInt::from_int64(v)
    assert_eq(big.to_int64(), Some(v))
    assert_eq(big.to_string(), v.to_string())
  }
}

///|
test "a thousand-digit integer survives the round trip" {
  let literal : Array[Byte] = [b'i']
  for _ in 0..<1000 {
    literal.push(b'7')
  }
  literal.push(b'e')
  let data = Bytes::from_array(literal[:])
  let value = must_decode(data)
  assert_eq(value.as_int(), None)
  let big = value.as_bigint().unwrap()
  assert_eq(big.digits().length(), 1000)
  assert_eq(@moonbit-bencode.encode(value), data)
}

///|
test "big integers compose with the rest of the format" {
  // A dictionary whose keys sort by raw byte order while one of the values
  // is a huge integer.
  let value = @moonbit-bencode.Value::dict_of([
    (
      b"b",
      @moonbit-bencode.Value::big_int(
        @moonbit-bencode.BigInt::parse(b"-99999999999999999999999999").unwrap(),
      ),
    ),
    (b"a", @moonbit-bencode.Value::int(1L)),
  ])
  let bytes = @moonbit-bencode.encode(value)
  assert_eq(bytes, b"d1:ai1e1:bi-99999999999999999999999999ee")
  let decoded = must_decode(bytes)
  assert_eq(decoded, value)
  // Reading the field back gives the same magnitude.
  let field = decoded.get(b"b").unwrap()
  assert_eq(
    field.as_bigint().unwrap().to_string(),
    "-99999999999999999999999999",
  )
}

///|
test "the two integer representations compare by value" {
  let small = @moonbit-bencode.Value::int(5L)
  let same = @moonbit-bencode.Value::big_int(
    @moonbit-bencode.BigInt::from_int64(5L),
  )
  let other = @moonbit-bencode.Value::big_int(
    @moonbit-bencode.BigInt::parse(b"5000000000000000000000").unwrap(),
  )
  assert_eq(small, same)
  assert_eq(same, small)
  assert_true(small != other)
  // A big value that happens to fit is still readable as an Int64.
  assert_eq(same.as_integer().unwrap().to_int64(), Some(5L))
  assert_true(other.as_integer().unwrap().to_int64() is None)
}
