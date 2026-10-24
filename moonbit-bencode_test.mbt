///|
/// Black-box tests for the public API of `moonbit-bencode`.
///
/// The suite is organised in five layers:
///
/// 1. the examples from BEP 3 itself,
/// 2. canonical encoding rules,
/// 3. malformed input handling (with byte offsets),
/// 4. the incremental stream decoder,
/// 5. a deterministic pseudo-random round-trip property test.

///|
/// Decode `data`, failing the test if the input is rejected.
fn must_decode(data : Bytes) -> @moonbit-bencode.Value {
  @moonbit-bencode.decode(data) catch {
    e => {
      println("unexpected decode error: \{e}")
      panic()
    }
  }
}

///|
/// Pull the next stream value, failing the test on malformed data.
/// `None` simply means "need more input".
fn next_or_fail(
  dec : @moonbit-bencode.StreamDecoder,
) -> @moonbit-bencode.Value? {
  dec.try_next() catch {
    e => {
      println("unexpected stream error: \{e}")
      panic()
    }
  }
}

///|
/// Drain every complete value currently buffered in `dec`.
fn drain(dec : @moonbit-bencode.StreamDecoder) -> Array[@moonbit-bencode.Value] {
  let out : Array[@moonbit-bencode.Value] = []
  while true {
    match next_or_fail(dec) {
      Some(v) => out.push(v)
      None => break
    }
  }
  out
}

///|
/// Decode `data` and require `DecodeError`; the checker inspects the error.
fn expect_error(
  data : Bytes,
  check : (@moonbit-bencode.DecodeError) -> Unit raise,
) -> Unit raise {
  try @moonbit-bencode.decode(data) catch {
    e => check(e)
  } noraise {
    _ => panic()
  }
}

///|
/// Decode `data` and compare its `Show` rendering with `expected`.
fn assert_decoded(data : Bytes, expected : String) -> Unit raise {
  let value = must_decode(data)
  assert_eq(value.to_string(), expected)
}

// ---------------------------------------------------------------------------
// 1. Examples from BEP 3
// ---------------------------------------------------------------------------

///|
test "bep3 integers" {
  assert_decoded(b"i42e", "42")
  assert_decoded(b"i0e", "0")
  assert_decoded(b"i-42e", "-42")
  assert_decoded(b"i9223372036854775807e", "9223372036854775807")
  assert_decoded(b"i-9223372036854775808e", "-9223372036854775808")
}

///|
test "bep3 strings" {
  assert_decoded(b"4:spam", "\"spam\"")
  assert_decoded(b"0:", "\"\"")
}

///|
test "bep3 lists" {
  assert_decoded(b"l4:spam4:eggse", "[\"spam\", \"eggs\"]")
  assert_decoded(b"le", "[]")
  assert_decoded(b"li1ei2ei3ee", "[1, 2, 3]")
}

///|
test "bep3 dictionaries" {
  assert_decoded(
    b"d3:cow3:moo4:spam4:eggse", "{\"cow\": \"moo\", \"spam\": \"eggs\"}",
  )
  assert_decoded(b"de", "{}")
  assert_decoded(
    b"d8:announce3:foo4:infod4:name3:baree", "{\"announce\": \"foo\", \"info\": {\"name\": \"bar\"}}",
  )
}

///|
test "bep3 torrent-like metainfo" {
  let data = b"d8:announce35:http://tracker.example.com/announce4:infod6:lengthi12345e4:name10:ubuntu.isoee"
  let value = must_decode(data)
  let length = value.get_path([b"info", b"length"]).unwrap()
  assert_eq(length.as_int().unwrap(), 12345L)
  let name = value.get_path([b"info", b"name"]).unwrap()
  assert_eq(name.as_str().unwrap(), b"ubuntu.iso")
  assert_true(value.get_path([b"info", b"missing"]) is None)
  assert_true(value.get_path([b"announce", b"nope"]) is None)
}

// ---------------------------------------------------------------------------
// 2. Canonical encoding
// ---------------------------------------------------------------------------

///|
test "encode emits sorted dictionary keys" {
  let value = must_decode(b"d4:spam4:eggs3:cow3:mooe")
  assert_eq(@moonbit-bencode.encode(value), b"d3:cow3:moo4:spam4:eggse")
  // Raw byte order, not length-first: "a" < "aa" < "b".
  let mixed = @moonbit-bencode.Value::dict_of([
    (b"b", @moonbit-bencode.Value::int(1L)),
    (b"aa", @moonbit-bencode.Value::int(2L)),
    (b"a", @moonbit-bencode.Value::int(3L)),
  ])
  assert_eq(@moonbit-bencode.encode(mixed), b"d1:ai3e2:aai2e1:bi1ee")
}

///|
test "decode of canonical input round-trips byte for byte" {
  let inputs = [
    b"i-9223372036854775808e", b"0:", b"4:spam", b"l4:spam4:eggse", b"d3:cow3:moo4:spam4:eggse",
    b"d8:announce3:foo4:infod4:name3:baree", b"d1:ai1e1:bi2ee", b"lli1eed1:a0:ee",
  ]
  for input in inputs {
    let value = must_decode(input)
    assert_eq(@moonbit-bencode.encode(value), input)
  }
}

///|
test "duplicate dictionary keys keep the last value" {
  let value = must_decode(b"d1:ai1e1:ai2ee")
  assert_eq(value.get(b"a").unwrap().as_int().unwrap(), 2L)
  assert_eq(@moonbit-bencode.encode(value), b"d1:ai2ee")
}

///|
test "binary-safe strings survive a round trip" {
  // Not valid UTF-8 on purpose.
  let value = @moonbit-bencode.Value::str(b"a\x00b\xffc\"d\\e")
  let bytes = @moonbit-bencode.encode(value)
  assert_eq(bytes, b"9:a\x00b\xffc\"d\\e")
  assert_eq(must_decode(bytes), value)
}

///|
test "value equality ignores dictionary order" {
  let a = must_decode(b"d1:ai1e1:bi2ee")
  let b = must_decode(b"d1:bi2e1:ai1ee")
  assert_eq(a, b)
  assert_true(a != @moonbit-bencode.Value::int(0L))
}

///|
test "value accessors report the variant" {
  let v = must_decode(b"l1:ai2ee")
  assert_true(v.as_int() is None)
  assert_true(v.as_str() is None)
  assert_true(v.as_dict() is None)
  assert_true(must_decode(b"i1e").as_list() is None)
  assert_true(must_decode(b"i1e").as_dict() is None)
  let items = v.as_list().unwrap()
  assert_eq(items.length(), 2)
  assert_eq(items[0].as_str().unwrap(), b"a")
  assert_eq(items[1].as_int().unwrap(), 2L)
}

// ---------------------------------------------------------------------------
// 3. Malformed input
// ---------------------------------------------------------------------------

///|
test "empty input" {
  expect_error(b"", fn(e) raise { assert_true(e is UnexpectedEnd(0)) })
}

///|
test "truncated integer" {
  expect_error(b"i42", fn(e) raise { assert_true(e is UnexpectedEnd(3)) })
  expect_error(b"i", fn(e) raise { assert_true(e is UnexpectedEnd(1)) })
  expect_error(b"i-", fn(e) raise { assert_true(e is UnexpectedEnd(2)) })
  expect_error(b"ie", fn(e) raise { assert_true(e is InvalidInteger(1)) })
  expect_error(b"i-e", fn(e) raise { assert_true(e is InvalidInteger(1)) })
}

///|
test "non-canonical integers are rejected" {
  expect_error(b"i042e", fn(e) raise { assert_true(e is InvalidInteger(1)) })
  expect_error(b"i-0e", fn(e) raise { assert_true(e is InvalidInteger(1)) })
  expect_error(b"i+1e", fn(e) raise { assert_true(e is InvalidInteger(1)) })
  expect_error(b"i 1e", fn(e) raise { assert_true(e is InvalidInteger(1)) })
}

///|
test "integers beyond Int64 decode instead of being rejected" {
  // BEP 3 puts no bound on integer size, so these must survive the round
  // trip rather than raising an error.
  let cases : Array[(Bytes, String)] = [
    (b"i9223372036854775808e", "9223372036854775808"),
    (b"i-9223372036854775809e", "-9223372036854775809"),
    (b"i99999999999999999999999e", "99999999999999999999999"),
    (
      b"i-170141183460469231731687303715884105728e", "-170141183460469231731687303715884105728",
    ),
  ]
  for (input, expected) in cases {
    let value = must_decode(input)
    assert_eq(value.to_string(), expected)
    assert_eq(@moonbit-bencode.encode(value), input)
    // The value is a BigInt, not an Int64.
    assert_true(value.as_bigint() is Some(_))
    assert_true(value.as_int() is None)
  }
}

///|
test "malformed strings" {
  expect_error(b"4:ab", fn(e) raise { assert_true(e is UnexpectedEnd(0)) })
  expect_error(b"04:spam", fn(e) raise { assert_true(e is InvalidLength(0)) })
  expect_error(b"x", fn(e) raise { assert_true(e is UnexpectedByte(b'x', 0)) })
  expect_error(b"3:ab", fn(e) raise { assert_true(e is UnexpectedEnd(0)) })
}

///|
test "unterminated containers" {
  expect_error(b"l", fn(e) raise { assert_true(e is UnexpectedEnd(1)) })
  expect_error(b"d", fn(e) raise { assert_true(e is UnexpectedEnd(1)) })
  expect_error(b"d1:a", fn(e) raise { assert_true(e is UnexpectedEnd(4)) })
  expect_error(b"li1e", fn(e) raise { assert_true(e is UnexpectedEnd(4)) })
}

///|
test "dictionary keys must be strings" {
  expect_error(b"di1e1:ae", fn(e) raise { assert_true(e is InvalidDictKey(1)) })
  expect_error(b"dli1ee1:ae", fn(e) raise {
    assert_true(e is InvalidDictKey(1))
  })
}

///|
test "trailing data" {
  expect_error(b"i1ei2e", fn(e) raise { assert_true(e is TrailingData(3)) })
  expect_error(b"4:spamx", fn(e) raise { assert_true(e is TrailingData(1)) })
  expect_error(b"lee", fn(e) raise { assert_true(e is TrailingData(1)) })
}

///|
test "error messages mention the offset" {
  let message = try {
    let _ = @moonbit-bencode.decode(b"i042e")
    "no error"
  } catch {
    e => e.to_string()
  }
  assert_eq(message, "malformed integer literal at byte 1")
}

///|
test "deep nesting is supported" {
  let depth = 200
  let data = b"l".repeat(depth) + b"i1e" + b"e".repeat(depth)
  let value = must_decode(data)
  let mut current = value
  for _ in 0..<(depth - 1) {
    current = current.as_list().unwrap()[0]
  }
  assert_eq(current.as_list().unwrap()[0].as_int().unwrap(), 1L)
  assert_eq(@moonbit-bencode.encode(value), data)
}

///|
test "nesting depth limit accepts the boundary" {
  let limit = @moonbit-bencode.max_nesting_depth()
  let data = b"l".repeat(limit) + b"i1e" + b"e".repeat(limit)
  let value = must_decode(data)
  assert_eq(@moonbit-bencode.encode(value), data)
}

///|
test "adversarial nesting is rejected, not crashed on" {
  // Without a depth limit this payload would exhaust the stack and take the
  // whole process down; it must surface as a normal decode error instead.
  let deep = b"l".repeat(10_000)
  expect_error(deep, fn(e) raise { assert_true(e is NestingTooDeep(512)) })
  let deep_dict = b"d1:a".repeat(10_000)
  expect_error(deep_dict, fn(e) raise { assert_true(e is NestingTooDeep(_)) })
  // Balanced but too deep: still a normal error.
  let balanced = b"l".repeat(513) + b"i1e" + b"e".repeat(513)
  expect_error(balanced, fn(e) raise { assert_true(e is NestingTooDeep(_)) })
}

///|
test "arbitrary bytes never panic" {
  // Deterministic pseudo-random inputs must always end in either a value or
  // a `DecodeError` — never an abort, never a stack overflow.
  let mut state : UInt64 = 0x9E3779B97F4A7C15
  for _ in 0..<800 {
    let s1 = next_random(state)
    let len = (s1 % 65).to_int()
    let (bytes, s2) = random_bytes(s1, len)
    state = s2
    let result = Some(@moonbit-bencode.decode(bytes)) catch { _ => None }
    // The only thing asserted here is that we reached this line at all; a
    // panic in the decoder would abort the test run instead.
    let _ = result
  }
}

// ---------------------------------------------------------------------------
// 4. StreamDecoder
// ---------------------------------------------------------------------------

///|
test "stream decoder handles a single value" {
  let dec = @moonbit-bencode.StreamDecoder::StreamDecoder()
  dec.feed(b"d3:cow3:moo4:spam4:eggse")
  let value = next_or_fail(dec)
  assert_true(value is Some(_))
  assert_eq(dec.pending(), 0)
  assert_true(next_or_fail(dec) is None)
}

///|
test "stream decoder yields nothing until the value is complete" {
  let dec = @moonbit-bencode.StreamDecoder::StreamDecoder()
  dec.feed(b"4:sp")
  assert_true(next_or_fail(dec) is None)
  assert_eq(dec.pending(), 4)
  dec.feed(b"am")
  let value = next_or_fail(dec)
  assert_eq(value.unwrap().as_str().unwrap(), b"spam")
  assert_eq(dec.pending(), 0)
}

///|
test "stream decoder splits chunks at every boundary" {
  // Feeding one byte at a time must produce exactly the same values as
  // feeding the whole payload at once.
  let payload = b"d3:cow3:moo4:spam4:eggse" + b"i42e" + b"l1:a2:bce"
  let whole = @moonbit-bencode.StreamDecoder::StreamDecoder()
  whole.feed(payload)
  let expected = drain(whole)
  assert_eq(expected.length(), 3)

  let drip = @moonbit-bencode.StreamDecoder::StreamDecoder()
  let actual : Array[@moonbit-bencode.Value] = []
  for i in 0..<payload.length() {
    drip.feed(payload[i:i + 1])
    for v in drain(drip) {
      actual.push(v)
    }
  }
  assert_eq(actual.length(), 3)
  for i in 0..<expected.length() {
    assert_eq(actual[i], expected[i])
  }
  assert_eq(drip.pending(), 0)
}

///|
test "stream decoder reports malformed data" {
  let dec = @moonbit-bencode.StreamDecoder::StreamDecoder()
  dec.feed(b"i042e")
  try dec.try_next() catch {
    InvalidInteger(pos) => assert_eq(pos, 1)
    _ => panic()
  } noraise {
    _ => panic()
  }
}

///|
test "stream decoder survives long streams (compaction)" {
  // Far more than the 4096-byte compaction threshold, so the internal
  // buffer is rebuilt many times while values keep decoding correctly.
  let dec = @moonbit-bencode.StreamDecoder::StreamDecoder()
  let mut count = 0
  let mut i = 0
  while i < 2000 {
    dec.feed(b"i1e")
    match next_or_fail(dec) {
      Some(v) => {
        assert_eq(v.as_int().unwrap(), 1L)
        count += 1
      }
      None => panic()
    }
    i += 1
  }
  assert_eq(count, 2000)
  assert_eq(dec.pending(), 0)
}

///|
test "stream decoder clear drops buffered bytes" {
  let dec = @moonbit-bencode.StreamDecoder::StreamDecoder()
  dec.feed(b"4:sp")
  assert_eq(dec.pending(), 4)
  dec.clear()
  assert_eq(dec.pending(), 0)
  dec.feed(b"i7e")
  assert_eq(next_or_fail(dec).unwrap().as_int().unwrap(), 7L)
}

// ---------------------------------------------------------------------------
// 5. Property test: deterministic pseudo-random round trips
// ---------------------------------------------------------------------------

///|
/// xorshift64 step, so the property test is fully deterministic.
fn next_random(state : UInt64) -> UInt64 {
  let mut x = state
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  x
}

///|
fn random_bytes(state : UInt64, len : Int32) -> (Bytes, UInt64) {
  let arr : Array[Byte] = []
  let mut s = state
  for _ in 0..<len {
    s = next_random(s)
    arr.push((s % 256).to_byte())
  }
  (Bytes::from_array(arr[:]), s)
}

///|
fn random_value(
  state : UInt64,
  depth : Int32,
) -> (@moonbit-bencode.Value, UInt64) {
  let s1 = next_random(state)
  let kind = s1 % 4
  if depth >= 3 || kind == 0 {
    // Leaf: a small integer, a byte string, or a big integer of 1..=40
    // digits — the third kind is what exercises the unbounded path.
    let s2 = next_random(s1)
    let leaf = s2 % 3
    if leaf == 0 {
      let n = (s2 / 3 % 2001).reinterpret_as_int64() - 1000L
      (@moonbit-bencode.Value::int(n), s2)
    } else if leaf == 1 {
      let s3 = next_random(s2)
      let ndigits = (s3 / 2 % 40).to_int() + 1
      let text : Array[Byte] = []
      if s3 % 5 == 0 {
        text.push(b'-')
      }
      let mut s = s3
      for _ in 0..<ndigits {
        s = next_random(s)
        text.push(b'0' + (s % 10).to_byte())
      }
      let literal = Bytes::from_array(text[:])
      match @moonbit-bencode.BigInt::parse(literal) {
        Some(big) => (@moonbit-bencode.Value::big_int(big), s)
        None => (@moonbit-bencode.Value::int(0L), s)
      }
    } else {
      let len = (s2 / 3 % 9).to_int()
      let (bytes, s3) = random_bytes(s2, len)
      (@moonbit-bencode.Value::str(bytes), s3)
    }
  } else if kind == 1 {
    let s2 = next_random(s1)
    let n = (s2 / 4 % 4).to_int()
    let items : Array[@moonbit-bencode.Value] = []
    let mut s = s2
    for _ in 0..<n {
      let (v, s3) = random_value(s, depth + 1)
      items.push(v)
      s = s3
    }
    (@moonbit-bencode.Value::list(items), s)
  } else {
    let s2 = next_random(s1)
    let n = (s2 / 4 % 4).to_int()
    let pairs : Array[(Bytes, @moonbit-bencode.Value)] = []
    let mut s = s2
    for i in 0..<n {
      let key = b"k\{i}"
      let (v, s3) = random_value(s, depth + 1)
      pairs.push((key, v))
      s = s3
    }
    (@moonbit-bencode.Value::dict_of(pairs), s)
  }
}

///|
test "random values round-trip through encode/decode" {
  let mut state : UInt64 = 0x2545F4914F6CDD1D
  for _ in 0..<300 {
    let (value, s) = random_value(state, 0)
    state = s
    let bytes = @moonbit-bencode.encode(value)
    let decoded = must_decode(bytes)
    assert_eq(decoded, value)
    // Encoding is stable: re-encoding the decoded value is a fixed point.
    assert_eq(@moonbit-bencode.encode(decoded), bytes)
    // The stream decoder agrees with the one-shot decoder.
    let dec = @moonbit-bencode.StreamDecoder::StreamDecoder()
    dec.feed(bytes)
    assert_eq(next_or_fail(dec).unwrap(), value)
  }
}

// ---------------------------------------------------------------------------
// 6. Rendering, equality edges and defensive paths
// ---------------------------------------------------------------------------

///|
test "show escapes binary payloads" {
  // a, quote, b, backslash, c, 0x01, d — not valid UTF-8 on purpose.
  let v = must_decode(b"7:a\"b\\c\x01d")
  assert_eq(v.to_string(), "\"a\\\"b\\\\c\\x01d\"")
  // Printable delimiters pass through untouched.
  assert_eq(must_decode(b"2:{}").to_string(), "\"{}\"")
}

///|
test "debug rendering covers every variant" {
  let value = must_decode(b"d1:bi2e2:aal1:xee")
  debug_inspect(
    value,
    content=(
      #|Dict({ "b": Int(2), "aa": List([Str("x")]) })
    ),
  )
}

///|
test "every decode error renders with its offset" {
  let cases : Array[(Bytes, String)] = [
    (b"", "unexpected end of input at byte 0"),
    (b"i42", "unexpected end of input at byte 3"),
    (b"x", "unexpected byte 0x78 at byte 0"),
    (b"ie", "malformed integer literal at byte 1"),
    (b"04:spam", "malformed byte-string length at byte 0"),
    (b"di1e1:ae", "dictionary key at byte 1 is not a byte string"),
    (
      b"l".repeat(513) + b"e".repeat(513),
      "containers nest deeper than 512 levels at byte 512",
    ),
    (b"i1ei2e", "3 trailing byte(s) after the top-level value"),
  ]
  for (input, expected) in cases {
    let message = try {
      let _ = @moonbit-bencode.decode(input)
      "no error"
    } catch {
      e => e.to_string()
    }
    assert_eq(message, expected)
  }
}

///|
test "expect failures point at the offending byte" {
  expect_error(b"4x", fn(e) raise { assert_true(e is UnexpectedByte(b'x', 1)) })
  expect_error(b"i1x", fn(e) raise { assert_true(e is UnexpectedByte(b'x', 2)) })
  expect_error(b"9999999999:x", fn(e) raise {
    assert_true(e is InvalidLength(0))
  })
}

///|
test "empty dictionary constructor" {
  let v = @moonbit-bencode.Value::dict()
  assert_eq(v.to_string(), "{}")
  let dict = v.as_dict().unwrap()
  assert_eq(dict.length(), 0)
  dict.set(b"k", @moonbit-bencode.Value::int(1L))
  assert_eq(v.to_string(), "{\"k\": 1}")
}

///|
test "equality detects every difference" {
  let base = must_decode(b"l1:ai2ee")
  // Same shape, different payload.
  assert_true(base != must_decode(b"l1:ai3ee"))
  // Different shape.
  assert_true(base != must_decode(b"l1:ae"))
  assert_true(must_decode(b"i1e") != must_decode(b"1:i"))
  // Same shape, different element.
  assert_true(must_decode(b"l1:ai2ee") != must_decode(b"l2:aai2ee"))
  // Dictionaries: same content, different order, are equal.
  assert_eq(must_decode(b"d1:ai1e1:bi2ee"), must_decode(b"d1:bi2e1:ai1ee"))
  // Dictionaries of different size are not.
  assert_true(must_decode(b"d1:ai1ee") != must_decode(b"d1:ai1e1:bi2ee"))
  // A missing key is not an unequal value.
  assert_true(must_decode(b"d1:ai1ee") != must_decode(b"d1:ai2ee"))
  // Same size, different key sets.
  assert_true(must_decode(b"d1:ai1e1:bi2ee") != must_decode(b"d1:ai1e1:ci2ee"))
  // Same keys, different value.
  assert_true(must_decode(b"d1:ai1e1:bi2ee") != must_decode(b"d1:ai1e1:bi3ee"))
}

///|
test "get_path stops at the first non-dictionary step" {
  let value = must_decode(b"d4:listl1:aee")
  assert_true(value.get_path([b"list", b"a"]) is None)
  assert_true(value.get_path([b"list"]) is Some(_))
  assert_true(value.get_path([]) is Some(_))
  assert_true(value.get_path([b"nope", b"deep"]) is None)
}
