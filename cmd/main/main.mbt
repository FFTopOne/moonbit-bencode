///|
/// Entry point of the `mbt-bencode` CLI. All logic lives in the `cli`
/// package; this file only wires the process exit code.
fn main {
  let code = @cli.run(@env.args())
  if code != 0 {
    // Surface failures to shell pipelines.
    @sys.exit(code)
  }
}
