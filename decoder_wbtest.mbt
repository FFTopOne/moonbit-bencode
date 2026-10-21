///|
/// White-box tests for decoder internals.
///
/// These reach defensive branches that the public API cannot: the string
/// decoder is only ever entered on a digit, so its "no digits" guard needs
/// to be driven directly.

///|
test "string body rejects a missing length prefix" {
  let cursor = Cursor::{ view: b"x:"[:], pos: 0, depth: 0, }
  try cursor.decode_str_body() catch {
    InvalidLength(pos) => assert_eq(pos, 0)
    _ => panic()
  } noraise {
    _ => panic()
  }
}

///|
test "cursor helpers" {
  let cursor = Cursor::{ view: b"ab"[:], pos: 0, depth: 0, }
  assert_true(cursor.peek() is Some(b'a'))
  let b = cursor.read_byte()
  assert_eq(b, b'a')
  assert_eq(cursor.pos, 1)
  cursor.expect(b'b')
  assert_eq(cursor.pos, 2)
  try cursor.read_byte() catch {
    UnexpectedEnd(pos) => assert_eq(pos, 2)
    _ => panic()
  } noraise {
    _ => panic()
  }
}

///|
test "integer body accepts the extremes" {
  assert_eq(
    decode(b"i9223372036854775807e").as_int().unwrap(),
    9223372036854775807L,
  )
  assert_eq(
    decode(b"i-9223372036854775808e").as_int().unwrap(),
    -9223372036854775808L,
  )
}
