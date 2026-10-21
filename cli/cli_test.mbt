///|
/// Tests for the CLI dispatch layer. File-touching commands are covered by
/// the library test suite and manual runs; here we pin the argument handling
/// and the type reporting used by `check`.

///|
test "usage without arguments" {
  assert_eq(@cli.run(["mbt-bencode"]), 2)
}

///|
test "unknown command" {
  assert_eq(@cli.run(["mbt-bencode", "bogus"]), 2)
}

///|
test "wrong argument counts" {
  assert_eq(@cli.run(["mbt-bencode", "decode"]), 2)
  assert_eq(@cli.run(["mbt-bencode", "decode", "a", "b"]), 2)
  assert_eq(@cli.run(["mbt-bencode", "canon", "only-one"]), 2)
  assert_eq(@cli.run(["mbt-bencode", "roundtrip"]), 2)
  assert_eq(@cli.run(["mbt-bencode", "check"]), 2)
}

///|
test "type_name reports the top-level variant" {
  assert_eq(@cli.type_name(@lib.Value::int(1L)), "integer")
  assert_eq(@cli.type_name(@lib.Value::str(b"x")), "byte string")
  assert_eq(@cli.type_name(@lib.Value::list([])), "list")
  assert_eq(@cli.type_name(@lib.Value::dict()), "dictionary")
}
