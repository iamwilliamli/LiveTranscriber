# Live Transcriber speech runtime

This directory vendors the four modules used by Live Transcriber from
[`soniqo/speech-swift`](https://github.com/soniqo/speech-swift) at revision
`a7fd06d6f68f167203fb995f7bdb8bc9ed10c179`.

The local package keeps iOS and macOS builds reproducible and adds an x86_64
compile-time half-precision compatibility layer. Xcode archives Swift Package
targets for both Mac architectures even though the application product is
Apple-Silicon-only; upstream uses `Swift.Float16`, which the Swift standard
library marks unavailable for x86_64 macOS. Apple Silicon builds continue to
use native `Swift.Float16` unchanged.

Upstream source remains under the Apache License 2.0 in `LICENSE`.
