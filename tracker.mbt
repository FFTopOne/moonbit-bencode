///|
/// Errors raised while interpreting a tracker response.
pub suberror TrackerError {
  /// The payload is not a dictionary, so it cannot be an announce response.
  NotADictionary
  /// A compact `peers` field is not a multiple of 6 bytes.
  MalformedCompactPeers(Int32)
  /// A compact `peers6` field is not a multiple of 18 bytes.
  MalformedCompactPeers6(Int32)
}

///|
pub impl Show for TrackerError with fn output(self, logger) {
  logger.write_string(
    match self {
      NotADictionary => "announce response is not a dictionary"
      MalformedCompactPeers(n) =>
        "compact peers field is \{n} bytes, not a multiple of 6"
      MalformedCompactPeers6(n) =>
        "compact peers6 field is \{n} bytes, not a multiple of 18"
    },
  )
}

///|
pub extend TrackerError with Show::{output, to_string}

///|
/// One peer address. `ip` holds the raw 4-byte IPv4 or 16-byte IPv6 address
/// exactly as the tracker sent it — no lossy text round trip.
pub struct Peer {
  ip : Bytes
  port : UInt16
}

///|
/// Build a peer from raw address bytes and a port.
pub fn Peer::Peer(ip : Bytes, port : UInt16) -> Peer {
  { ip, port, }
}

///|
/// The raw address bytes (4 for IPv4, 16 for IPv6).
pub fn Peer::ip(self : Peer) -> Bytes {
  self.ip
}

///|
/// The peer's port.
pub fn Peer::port(self : Peer) -> UInt16 {
  self.port
}

///|
/// Human-readable address: dotted quad for IPv4, colon-separated 16-bit
/// groups for IPv6 (no `::` compression).
pub fn Peer::ip_string(self : Peer) -> String {
  let sb = StringBuilder()
  let n = self.ip.length()
  if n == 4 {
    for i in 0..<n {
      if i > 0 {
        sb.write_char('.')
      }
      sb.write_string(self.ip[i].to_int().to_string())
    }
  } else {
    let mut i = 0
    while i + 1 < n {
      if i > 0 {
        sb.write_char(':')
      }
      sb.write_string(self.ip[i].to_hex())
      sb.write_string(self.ip[i + 1].to_hex())
      i += 2
    }
  }
  sb.to_string()
}

///|
/// A decoded announce response. Every scalar field is optional: trackers are
/// allowed to omit any of them, and a failure response only carries
/// `failure reason`.
pub struct AnnounceResponse {
  interval : Int64?
  min_interval : Int64?
  complete : Int64?
  incomplete : Int64?
  failure_reason : Bytes?
  warning_message : Bytes?
  peers : Array[Peer]
}

///|
/// Seconds between announcements.
pub fn AnnounceResponse::interval(self : Self) -> Int64? {
  self.interval
}

///|
/// Minimum announcement interval the tracker accepts, if advertised.
pub fn AnnounceResponse::min_interval(self : Self) -> Int64? {
  self.min_interval
}

///|
/// Number of seeders, if reported.
pub fn AnnounceResponse::complete(self : Self) -> Int64? {
  self.complete
}

///|
/// Number of leechers, if reported.
pub fn AnnounceResponse::incomplete(self : Self) -> Int64? {
  self.incomplete
}

///|
/// Present when the tracker refused the request.
pub fn AnnounceResponse::failure_reason(self : Self) -> Bytes? {
  self.failure_reason
}

///|
/// Optional warning the client should show to the user.
pub fn AnnounceResponse::warning_message(self : Self) -> Bytes? {
  self.warning_message
}

///|
/// The peers, whether they arrived in compact form (`peers` / `peers6`,
/// BEP 23) or as a list of dictionaries with `ip` and `port` fields.
pub fn AnnounceResponse::peers(self : Self) -> Array[Peer] {
  self.peers
}

///|
/// Interpret a decoded value as an announce response.
///
/// Raises `TrackerError` only for structural problems (not a dictionary, or a
/// compact peer field with an impossible length); missing optional fields are
/// reported as `None`.
pub fn AnnounceResponse::parse(
  value : Value,
) -> AnnounceResponse raise TrackerError {
  guard value.as_dict() is Some(_) else { raise NotADictionary }
  let peers : Array[Peer] = []
  match value.get(b"peers") {
    Some(compact) =>
      match compact.as_str() {
        Some(bytes) => parse_compact_peers(bytes, 6, peers)
        None =>
          match compact.as_list() {
            Some(items) => parse_dict_peers(items, peers)
            None => ()
          }
      }
    None => ()
  }
  match value.get(b"peers6") {
    Some(compact6) =>
      match compact6.as_str() {
        Some(bytes) => parse_compact_peers(bytes, 18, peers)
        None => ()
      }
    None => ()
  }
  {
    interval: int_field(value, b"interval"),
    min_interval: int_field(value, b"min interval"),
    complete: int_field(value, b"complete"),
    incomplete: int_field(value, b"incomplete"),
    failure_reason: str_field(value, b"failure reason"),
    warning_message: str_field(value, b"warning message"),
    peers,
  }
}

///|
fn int_field(value : Value, key : Bytes) -> Int64? {
  match value.get(key) {
    Some(v) => v.as_int()
    None => None
  }
}

///|
fn str_field(value : Value, key : Bytes) -> Bytes? {
  match value.get(key) {
    Some(v) => v.as_str()
    None => None
  }
}

///|
/// Decode the compact form: `stride` bytes per peer, address first, then the
/// port as two big-endian bytes.
fn parse_compact_peers(
  data : Bytes,
  stride : Int32,
  out : Array[Peer],
) -> Unit raise TrackerError {
  let len = data.length()
  guard len % stride == 0 else {
    if stride == 6 {
      raise MalformedCompactPeers(len)
    } else {
      raise MalformedCompactPeers6(len)
    }
  }
  let addr_len = stride - 2
  let mut i = 0
  while i < len {
    let ip = data[i:i + addr_len].to_owned()
    let hi = data[i + addr_len].to_int()
    let lo = data[i + addr_len + 1].to_int()
    out.push(Peer::{ ip, port: (hi * 256 + lo).to_uint16(), })
    i += stride
  }
}

///|
/// Decode the dictionary-list form: `[{ ip: "1.2.3.4", port: 6881 }, ...]`.
///
/// The address arrives as text here, but `Peer` always stores raw bytes, so
/// the dotted quad is parsed into four bytes. Entries whose address or port
/// cannot be understood are skipped rather than failing the whole response.
fn parse_dict_peers(items : Array[Value], out : Array[Peer]) -> Unit {
  for item in items {
    let addr = str_field(item, b"ip")
    let port = int_field(item, b"port")
    match (addr, port) {
      (Some(text), Some(p)) =>
        match parse_ipv4(text) {
          Some(ip) => out.push(Peer::{ ip, port: p.to_uint16(), })
          None => ()
        }
      _ => ()
    }
  }
}

///|
/// Parse a dotted quad ("1.2.3.4") into four bytes, rejecting anything that is
/// not exactly four decimal octets in 0..=255.
fn parse_ipv4(text : Bytes) -> Bytes? {
  let octets : Array[Byte] = []
  let mut value = 0
  let mut digits = 0
  for b in text {
    if b == b'.' {
      if digits == 0 {
        return None
      }
      octets.push(value.to_byte())
      value = 0
      digits = 0
    } else if b >= b'0' && b <= b'9' {
      value = value * 10 + (b - b'0').to_int()
      if value > 255 {
        return None
      }
      digits += 1
    } else {
      return None
    }
  }
  if digits == 0 {
    return None
  }
  octets.push(value.to_byte())
  guard octets.length() == 4 else { return None }
  Some(Bytes::from_array(octets[:]))
}
