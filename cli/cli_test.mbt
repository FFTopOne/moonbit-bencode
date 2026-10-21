///|
/// End-to-end tests for the CLI: every file-touching command is exercised
/// against real files in a temporary directory, then cleaned up.

///|
fn with_temp_dir(f : (String) -> Unit raise) -> Unit raise {
  let dir = "tmp_cli_test"
  if @fs.path_exists(dir) {
    @fs.remove_file("\{dir}/in.bencode") catch {
      _ => ()
    }
    @fs.remove_file("\{dir}/out.bencode") catch {
      _ => ()
    }
    @fs.remove_file("\{dir}/bad.bencode") catch {
      _ => ()
    }
    @fs.remove_dir(dir) catch {
      _ => ()
    }
  }
  @fs.create_dir(dir)
  f(dir)
  @fs.remove_file("\{dir}/in.bencode") catch {
    _ => ()
  }
  @fs.remove_file("\{dir}/out.bencode") catch {
    _ => ()
  }
  @fs.remove_file("\{dir}/bad.bencode") catch {
    _ => ()
  }
  @fs.remove_dir(dir) catch {
    _ => ()
  }
}

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

///|
test "every command succeeds on a valid payload" {
  with_temp_dir(fn(dir) raise {
    let src = "\{dir}/in.bencode"
    // Non-canonical on purpose: keys out of order.
    @fs.write_bytes_to_file(src, b"d4:spam4:eggs3:cow3:mooe")
    assert_eq(@cli.run(["mbt-bencode", "decode", src]), 0)
    assert_eq(@cli.run(["mbt-bencode", "check", src]), 0)
    assert_eq(@cli.run(["mbt-bencode", "roundtrip", src]), 0)
  })
}

///|
test "canon rewrites a payload into canonical form" {
  with_temp_dir(fn(dir) raise {
    let src = "\{dir}/in.bencode"
    let dst = "\{dir}/out.bencode"
    @fs.write_bytes_to_file(src, b"d4:spam4:eggs3:cow3:mooe")
    assert_eq(@cli.run(["mbt-bencode", "canon", src, dst]), 0)
    let out = @fs.read_file_to_bytes(dst)
    assert_eq(out, b"d3:cow3:moo4:spam4:eggse")
  })
}

///|
test "malformed payloads exit non-zero" {
  with_temp_dir(fn(dir) raise {
    let bad = "\{dir}/bad.bencode"
    let dst = "\{dir}/out.bencode"
    @fs.write_bytes_to_file(bad, b"i042e")
    assert_eq(@cli.run(["mbt-bencode", "check", bad]), 1)
    assert_eq(@cli.run(["mbt-bencode", "decode", bad]), 1)
    assert_eq(@cli.run(["mbt-bencode", "roundtrip", bad]), 1)
    assert_eq(@cli.run(["mbt-bencode", "canon", bad, dst]), 1)
  })
}

///|
test "missing files exit with the usage code" {
  with_temp_dir(fn(dir) raise {
    assert_eq(@cli.run(["mbt-bencode", "check", "\{dir}/nope.bencode"]), 2)
    assert_eq(@cli.run(["mbt-bencode", "decode", "\{dir}/nope.bencode"]), 2)
    assert_eq(@cli.run(["mbt-bencode", "roundtrip", "\{dir}/nope.bencode"]), 2)
  })
}

///|
test "unwritable output path exits non-zero" {
  with_temp_dir(fn(dir) raise {
    let src = "\{dir}/in.bencode"
    @fs.write_bytes_to_file(src, b"i1e")
    assert_eq(
      @cli.run(["mbt-bencode", "canon", src, "\{dir}/no/such/dir/out.bencode"]),
      1,
    )
  })
}
