///|
/// The `mbt-bencode` command line interface.
///
/// Run it from the project root with
/// `moon run cmd/main --target native -- <command> [args]`.
///
/// Commands:
///
/// - `decode <file>`: print the decoded value as a tree,
/// - `check <file>`: validate the payload and report its shape,
/// - `canon <in> <out>`: re-encode in canonical form,
/// - `roundtrip <file>`: verify decode -> encode -> decode stability.

///|
/// Command dispatch. Returns the process exit code.
pub fn run(args : Array[String]) -> Int32 {
  if args.length() < 2 {
    print_usage()
    return 2
  }
  let command = args[1]
  let rest = args[2:]
  if command == "decode" {
    cmd_decode(rest)
  } else if command == "check" {
    cmd_check(rest)
  } else if command == "canon" {
    cmd_canon(rest)
  } else if command == "roundtrip" {
    cmd_roundtrip(rest)
  } else {
    println("unknown command: \{command}")
    print_usage()
    2
  }
}

///|
fn print_usage() -> Unit {
  println(
    "|mbt-bencode — bencode (BEP 3) toolkit|\n|\n|usage: mbt-bencode <command> [args]\n|\n|commands:\n|  decode <file>       print the decoded value tree\n|  check <file>        validate the payload\n|  canon <in> <out>    re-encode in canonical form\n|  roundtrip <file>    verify decode/encode stability|",
  )
}

///|
fn cmd_decode(args : ArrayView[String]) -> Int32 {
  guard args.length() == 1 else {
    println("usage: mbt-bencode decode <file>")
    return 2
  }
  let data = @fs.read_file_to_bytes(args[0]) catch {
    IOError(msg) => {
      println("error: cannot read \{args[0]}: \{msg}")
      return 2
    }
  }
  let value = @lib.decode(data) catch {
    e => {
      println("error: \{e}")
      return 1
    }
  }
  println(value.to_string())
  0
}

///|
fn cmd_check(args : ArrayView[String]) -> Int32 {
  guard args.length() == 1 else {
    println("usage: mbt-bencode check <file>")
    return 2
  }
  let data = @fs.read_file_to_bytes(args[0]) catch {
    IOError(msg) => {
      println("error: cannot read \{args[0]}: \{msg}")
      return 2
    }
  }
  let value = @lib.decode(data) catch {
    e => {
      println("invalid: \{e}")
      return 1
    }
  }
  println("ok: \{data.length()} bytes, top-level \{type_name(value)}")
  0
}

///|
fn cmd_canon(args : ArrayView[String]) -> Int32 {
  guard args.length() == 2 else {
    println("usage: mbt-bencode canon <in> <out>")
    return 2
  }
  let data = @fs.read_file_to_bytes(args[0]) catch {
    IOError(msg) => {
      println("error: cannot read \{args[0]}: \{msg}")
      return 2
    }
  }
  let value = @lib.decode(data) catch {
    e => {
      println("error: \{e}")
      return 1
    }
  }
  let canonical = @lib.encode(value)
  @fs.write_bytes_to_file(args[1], canonical) catch {
    IOError(msg) => {
      println("error: cannot write \{args[1]}: \{msg}")
      return 1
    }
  }
  println(
    "ok: \{data.length()} bytes -> \{canonical.length()} bytes (canonical)",
  )
  0
}

///|
fn cmd_roundtrip(args : ArrayView[String]) -> Int32 {
  guard args.length() == 1 else {
    println("usage: mbt-bencode roundtrip <file>")
    return 2
  }
  let data = @fs.read_file_to_bytes(args[0]) catch {
    IOError(msg) => {
      println("error: cannot read \{args[0]}: \{msg}")
      return 2
    }
  }
  let first = @lib.decode(data) catch {
    e => {
      println("error: \{e}")
      return 1
    }
  }
  let encoded = @lib.encode(first)
  let second = @lib.decode(encoded) catch {
    e => {
      println("error: re-decoding failed: \{e}")
      return 1
    }
  }
  if first != second || @lib.encode(second) != encoded {
    println("unstable: value changed across the round trip")
    return 1
  }
  println("stable: \{data.length()} bytes -> \{encoded.length()} bytes")
  0
}

///|
/// Name of the top-level variant, for `check` output.
pub fn type_name(value : @lib.Value) -> String {
  if value.as_int() is Some(_) || value.as_bigint() is Some(_) {
    "integer"
  } else if value.as_str() is Some(_) {
    "byte string"
  } else if value.as_list() is Some(_) {
    "list"
  } else {
    "dictionary"
  }
}
