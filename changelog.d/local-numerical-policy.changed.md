Long numerical suites, proof/property runs, accuracy and AD references,
latency/determinism benchmarks, and book-example evaluations are optional
local tools. They are not pre-push, merge, or release blockers and never run
in scheduled, manual, or release CI. The nightly workflow was removed.
Hosted publication still builds the canonical release assets once and checks
the actual payload hashes, artifact integrity, and byte-identical manifest.
This is an explicit Shoals-only policy divergence.
CI retains the measured expiry-only property smoke, capped at 60 seconds per
invocation, alongside compilation and offline checks.
