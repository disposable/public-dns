# Probe Corpus Summary

- Corpus version: `dev`
- Schema version: `2`
- Generator version: `0.1.0`
- Generated at: `2026-04-05T04:45:43Z`
- Candidates seen: `53`
- Accepted probes: `49`
- Rejected probes: `4`

## Accepted Counts

- `negative_generated`: 7
- `positive_consensus`: 7
- `positive_exact`: 35

## Rejected By Reason

- `exact_rrset_mismatch`: 4

## Baseline Resolvers

- `1.1.1.1`
- `9.9.9.9`
- `8.8.8.8`

## Consensus Metadata

- `expected_nameservers` is generation metadata captured from the accepted baseline
  quorum.
- Runtime validation for `consensus_match` still uses live baseline comparison.

## Dropped Seeds

- `z.nic.de.` -> `exact_rrset_mismatch`
- `z.nic.de.` -> `exact_rrset_mismatch`
- `b.dns.jp.` -> `exact_rrset_mismatch`
- `h.dns.jp.` -> `exact_rrset_mismatch`

## Sources

- https://www.iana.org/domains/root/servers
- https://www.iana.org/domains/root/db/de.html
- https://www.iana.org/domains/root/db/uk.html
- https://www.iana.org/domains/root/db/jp.html
- https://www.iana.org/domains/root/db/fr.html
- https://www.iana.org/domains/root/db/nl.html
- https://www.iana.org/domains/root/db/br.html
- https://www.iana.org/domains/root/db/au.html
