# ADR 0001: Adopt XHTTP Anti-Censorship Baseline

- Status: Accepted
- Date: 2026-07-26

## Context

Transport defaults changed upstream, client applications preserve Host
settings inconsistently, and mutable container tags make deployed behavior
difficult to audit. The project also carried several equal-looking profiles
with different security goals.

## Decision

The canonical profile is VLESS XHTTP on a Unix socket behind Caddy TLS and a
cover service. It retains the tested XHTTP padding/obfuscation values.

Client connection policy is explicit in the Remnawave Host override:

- XHTTP XMUX uses `maxConnections: "6"`;
- XHTTP XMUX does not set `maxConcurrency`;
- general outbound MUX remains unset;
- supported clients use Xray-core `v26.6.27` or newer.

The Node profile does not contain XMUX. Runtime images are pinned by version
and immutable multi-platform digest. The node status command fails when the
runtime no longer matches this policy.

XTLS-Vision and plain XHTTP are deprecated profiles under
`panel-profiles/legacy/`. They receive critical fixes only. Fixed-pair bridge
profiles are removed; future multihop work requires a separately designed
managed topology.

## Consequences

Operators must apply both the Node profile and Host override, then refresh
subscriptions. Older or lossy clients are unsupported. Image upgrades require
an explicit reviewed pin update. The baseline favors security first, privacy
second, and throughput third while treating all three as required design
inputs.
