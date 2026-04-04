# Probe Corpus Summary

- Corpus version: `dev`
- Schema version: `2`
- Generator version: `0.1.0`
- Generated at: `2026-04-04T14:15:17Z`
- Candidates seen: `19`
- Accepted probes: `17`
- Rejected probes: `2`

## Accepted Counts

- `negative_generated`: 4
- `positive_consensus`: 3
- `positive_exact`: 10

## Rejected By Reason

- `exact_rrset_mismatch`: 2

## Baseline Resolvers

- `1.1.1.1`
- `9.9.9.9`
- `8.8.8.8`

## Consensus Metadata

- `expected_nameservers` is generation metadata captured from the accepted baseline
  quorum.
- Runtime validation for `consensus_match` still uses live baseline comparison.

## Dropped Seeds

- `b.dns.jp.` -> `exact_rrset_mismatch`
- `h.dns.jp.` -> `exact_rrset_mismatch`

## Sources

- https://www.iana.org/domains/root/servers
- https://www.iana.org/domains/root/db/de.html
- https://www.iana.org/domains/root/db/uk.html
- https://www.iana.org/domains/root/db/jp.html
