---
id: RFC-0002
title: Reorient Supply from a Canonical Crawler to an LLM Evidence Feed
status: superseded
owner: maintainer
---

# Reorient Supply from a Canonical Crawler to an LLM Evidence Feed

> **Superseded (2026-08-27).** Supply 기능 자체가 제거되어 이 재정향 제안은 대상이 없다.

## Purpose

Preserve the 2026-08-04 assessment of the Supply implementation before more
work is added. The original product goal was to collect shopping evidence and
feed a bounded, useful representation to an LLM for comparison and analysis.
The current implementation instead spends most of its complexity proving and
normalizing a provider-specific crawl into a stable canonical contract.

This document is a proposal and restart point, not an accepted replacement for
the current Supply contracts. The verified implementation remains authoritative
until a smaller path is approved and proven.

## Assessment

The present architecture is poorly matched to the original product goal:

- Naver DOM and response structures remain changeable even after extensive
  transport, ownership, URL, schema, and domain validation.
- Base64, decoded-length, and SHA-256 checks detect transport and implementation
  mistakes but do not make a changing provider page stable. SHA-256 is not an
  authentication boundary because the same Python worker supplies the body and
  digest.
- Strict card ownership, response enrichment, canonical field mapping, coverage
  states, stable error codes, persistence, and public contracts make each
  provider change expensive to diagnose and repair.
- Parser failure currently tends to prevent useful downstream analysis instead
  of degrading to a bounded document that an LLM can still inspect.
- Development and verification cost has exceeded the value demonstrated by the
  current search, detail, review, and media results.

The code-size snapshot at the time of this assessment illustrates the shape,
not a permanent metric:

| Component | Production lines | Test lines |
| --- | ---: | ---: |
| `raw_html_tree.rs` exploration | about 297 | 0 |
| `naver_search.rs` | about 980 | about 1,300 |
| `capture.rs` | about 720 | about 860 |
| extractor-client `lib.rs` | about 410 | about 600 |
| `supply_search.rs` | about 280 | about 220 |

Tests explain much of the repository size, but production complexity is still
substantially larger than the exploratory extractor because it attempts to
classify every ambiguity and boundary failure.

## What remains useful

Do not assume the entire implementation must be discarded. The following
pieces can support a smaller design:

- Scrapling-managed, owner-profile browser execution and manual login;
- bounded navigation, scrolling, capture count, byte size, and timeout;
- the Rust CLI and process supervision boundary;
- owner-only SQLite references and capture metadata;
- privacy-safe logging and absence of cookies, headers, and raw personal data
  from normal logs;
- deterministic fixtures that represent provider shapes actually encountered.

## Candidate smaller product shape

The next design review should begin from this flow:

```text
browser capture
    -> bounded raw or lightly cleaned document
    -> optional provider extractor
    -> LLM evidence selection and comparison
```

Rust would own request bounds, worker supervision, storage references, document
selection, and LLM orchestration. Python/Scrapling would own browser behavior
and raw capture. A provider extractor would be an optional projection rather
than a condition for preserving useful evidence.

A minimal conceptual record is:

```text
capture
├── reference
├── source
├── query
├── final origin or private navigation reference
├── captured_at
├── content_type
├── bounded content
└── small metadata
```

Textual UTF-8 HTML or JSON need not automatically use Base64 or SHA-256 when it
is passed once and immediately consumed. Binary media still needs a binary-safe
encoding across JSON, and persisted content-addressed media can still use a
digest for deduplication and corruption detection.

## Required decisions before implementation

Do not continue extending the current canonical parser until these questions
are answered explicitly:

1. Is the product output a stable shopping database, or bounded evidence for an
   LLM? The latter was the original goal.
2. Which raw or cleaned evidence may be retained, for how long, and under which
   privacy boundary?
3. When structured extraction fails, should the operation return a usable
   document with `structured_projection_unavailable` rather than fail entirely?
4. Which fields truly require deterministic parsing before an LLM sees them?
   Likely candidates are price, currency, seller, direct target, and provenance;
   everything else requires justification.
5. Which current transport checks prevent a demonstrated failure, and which
   merely duplicate local pipe and JSON framing guarantees?
6. Can one vertical experiment prove useful comparison quality with materially
   less provider-specific code before the current path is replaced?

## Proposed experiment

Build no production replacement first. Use one bounded, owner-operated capture
and compare three representations:

1. current canonical structured output;
2. a small deterministic item projection;
3. bounded cleaned HTML or JSON supplied as LLM evidence.

Measure implementation size, failure behavior after a fixture mutation, token
cost, and comparison usefulness. Adopt a replacement only if the smaller path
keeps privacy and bounds while continuing to produce useful analysis when the
provider structure changes.

## Non-decisions

- This RFC does not authorize persisting arbitrary raw browsing data.
- It does not remove the current Supply contracts, migrations, or release gates.
- It does not permit direct replay of browser-private endpoints.
- It does not declare LLM output factual without provenance and bounded source
  evidence.
- It does not claim Base64 or SHA-256 are universally useless; it limits their
  justification to binary transport, persistence integrity, deduplication, or a
  reproduced failure.

## Related

- [Sherpa roadmap](../roadmap/README.md)
- [Live evidence history](../testing/live-evidence.md)
