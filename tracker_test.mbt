///|
/// Tests for the typed announce-response helpers (BEP 3 / BEP 23).

///|
/// Build `{ "interval": 1800, "peers": <payload> }` for the given peers field.
fn response_with_peers(
  peers : @moonbit-bencode.Value,
) -> @moonbit-bencode.Value {
  @moonbit-bencode.Value::dict_of([
    (b"interval", @moonbit-bencode.Value::int(1800L)),
    (b"peers", peers),
  ])
}

///|
test "compact peers (BEP 23) decode to addresses and ports" {
  // 127.0.0.1:6881 and 5.6.7.8:51413, six bytes each.
  let compact = b"\x7f\x00\x00\x01\x1a\xe1\x05\x06\x07\x08\xc8\xd5"
  let response = @moonbit-bencode.AnnounceResponse::parse(
    response_with_peers(@moonbit-bencode.Value::str(compact)),
  )
  let peers = response.peers()
  assert_eq(peers.length(), 2)
  assert_eq(peers[0].ip_string(), "127.0.0.1")
  assert_eq(peers[0].port(), (6881 : UInt16))
  assert_eq(peers[1].ip_string(), "5.6.7.8")
  assert_eq(peers[1].port(), (51413 : UInt16))
  // The raw address stays binary: four bytes, never text.
  assert_eq(peers[0].ip().length(), 4)
}

///|
test "dictionary-list peers decode too" {
  let value = response_with_peers(
    @moonbit-bencode.Value::list([
      @moonbit-bencode.Value::dict_of([
        (b"ip", @moonbit-bencode.Value::str(b"1.2.3.4")),
        (b"port", @moonbit-bencode.Value::int(6881L)),
      ]),
      @moonbit-bencode.Value::dict_of([
        (b"ip", @moonbit-bencode.Value::str(b"9.9.9.9")),
        (b"port", @moonbit-bencode.Value::int(80L)),
      ]),
    ]),
  )
  let response = @moonbit-bencode.AnnounceResponse::parse(value)
  let peers = response.peers()
  assert_eq(peers.length(), 2)
  assert_eq(peers[1].ip_string(), "9.9.9.9")
  assert_eq(peers[1].port(), (80 : UInt16))
  assert_eq(response.interval(), Some(1800L))
}

///|
test "incomplete peer entries are skipped, not fatal" {
  let value = response_with_peers(
    @moonbit-bencode.Value::list([
      @moonbit-bencode.Value::dict_of([
        (b"ip", @moonbit-bencode.Value::str(b"1.2.3.4")),
      ]),
      @moonbit-bencode.Value::dict_of([
        (b"port", @moonbit-bencode.Value::int(6881L)),
      ]),
      @moonbit-bencode.Value::dict_of([
        (b"ip", @moonbit-bencode.Value::str(b"5.6.7.8")),
        (b"port", @moonbit-bencode.Value::int(6881L)),
      ]),
    ]),
  )
  let response = @moonbit-bencode.AnnounceResponse::parse(value)
  assert_eq(response.peers().length(), 1)
  assert_eq(response.peers()[0].ip_string(), "5.6.7.8")
}

///|
test "ipv6 peers use 18-byte entries" {
  let addr = b"\x20\x01\x0d\xb8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01"
  let peers = @moonbit-bencode.Value::str(addr + b"\x1a\xe1")
  let value = @moonbit-bencode.Value::dict_of([
    (b"peers6", peers),
    (b"interval", @moonbit-bencode.Value::int(60L)),
  ])
  let response = @moonbit-bencode.AnnounceResponse::parse(value)
  assert_eq(response.peers().length(), 1)
  assert_eq(
    response.peers()[0].ip_string(),
    "2001:0db8:0000:0000:0000:0000:0000:0001",
  )
  assert_eq(response.peers()[0].port(), (6881 : UInt16))
  assert_eq(response.peers()[0].ip().length(), 16)
}

///|
test "failure responses carry a reason and no peers" {
  let value = @moonbit-bencode.Value::dict_of([
    (b"failure reason", @moonbit-bencode.Value::str(b"torrent not found")),
    (b"warning message", @moonbit-bencode.Value::str(b"")),
    (b"interval", @moonbit-bencode.Value::int(1800L)),
  ])
  let response = @moonbit-bencode.AnnounceResponse::parse(value)
  assert_eq(response.failure_reason(), Some(b"torrent not found"))
  assert_eq(response.warning_message(), Some(b""))
  assert_eq(response.interval(), Some(1800L))
  assert_eq(response.peers().length(), 0)
  // Fields the tracker omitted stay None rather than defaulting to zero.
  assert_true(response.complete() is None)
  assert_true(response.incomplete() is None)
  assert_true(response.min_interval() is None)
}

///|
test "all scalar fields are extracted" {
  let value = @moonbit-bencode.Value::dict_of([
    (b"complete", @moonbit-bencode.Value::int(12L)),
    (b"incomplete", @moonbit-bencode.Value::int(34L)),
    (b"interval", @moonbit-bencode.Value::int(1800L)),
    (b"min interval", @moonbit-bencode.Value::int(900L)),
  ])
  let response = @moonbit-bencode.AnnounceResponse::parse(value)
  assert_eq(response.complete(), Some(12L))
  assert_eq(response.incomplete(), Some(34L))
  assert_eq(response.interval(), Some(1800L))
  assert_eq(response.min_interval(), Some(900L))
}

///|
test "malformed compact peers are rejected" {
  // Seven bytes cannot hold a whole number of six-byte peers.
  let value = response_with_peers(
    @moonbit-bencode.Value::str(b"\x7f\x00\x00\x01\x1a\xe1\x00"),
  )
  try @moonbit-bencode.AnnounceResponse::parse(value) catch {
    MalformedCompactPeers(n) => assert_eq(n, 7)
    _ => panic()
  } noraise {
    _ => panic()
  }
  // Likewise for the 18-byte IPv6 form.
  let value6 = @moonbit-bencode.Value::dict_of([
    (b"peers6", @moonbit-bencode.Value::str(b"\x00\x00\x00\x00\x00\x00")),
  ])
  try @moonbit-bencode.AnnounceResponse::parse(value6) catch {
    MalformedCompactPeers6(n) => assert_eq(n, 6)
    _ => panic()
  } noraise {
    _ => panic()
  }
}

///|
test "a non-dictionary payload is rejected" {
  try
    @moonbit-bencode.AnnounceResponse::parse(@moonbit-bencode.Value::int(1L))
  catch {
    NotADictionary => ()
    _ => panic()
  } noraise {
    _ => panic()
  }
}

///|
test "an empty dictionary parses into an empty response" {
  let response = @moonbit-bencode.AnnounceResponse::parse(
    @moonbit-bencode.Value::dict(),
  )
  assert_eq(response.peers().length(), 0)
  assert_true(response.interval() is None)
  assert_true(response.failure_reason() is None)
}

///|
test "tracker errors render with context" {
  let message = try {
    let _ = @moonbit-bencode.AnnounceResponse::parse(
      @moonbit-bencode.Value::str(b"nope"),
    )
    "no error"
  } catch {
    e => e.to_string()
  }
  assert_eq(message, "announce response is not a dictionary")
}
