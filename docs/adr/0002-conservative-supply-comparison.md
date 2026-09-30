---
id: ADR-0002
title: Conservative Supply Price Comparison
status: superseded
owner: maintainer
---

# ADR-0002: Conservative Supply Price Comparison

> **Superseded (2026-08-27).** Supply(쇼핑 비교) 기능이 제거되었다. CLI 에 대응 명령이
> 없었고 스킬도 함께 걷어냈다. 이 문서는 당시 보수적 비교 원칙을 어떻게 정했는지에 대한
> 기록으로만 남는다.

## Context

Marketplace cards and detail pages frequently omit shipping, required fees,
option-specific prices, coupon eligibility, or current stock. Treating an
unknown amount as zero or subtracting an advertised coupon can manufacture a
false cheapest offer. AI output is also unsuitable as an arithmetic authority.

## Decision

Rust alone computes landed prices with checked integer minor-unit arithmetic.
Unknown required terms make an offer incomparable. Unverified coupons are not
subtracted and produce an upper-bound result. A definitive winner is emitted
only when every candidate is comparable and every comparable coupon state is
verified. Product identity, exact option, condition, quantity, currency,
availability, and evidence are hard gates rather than ranking hints.

## Consequences

- Sherpa may decline to name a winner even when one visible subtotal is lower.
- More collection or a separate cart read-back can improve confidence without
  changing arithmetic policy.
- Historical observations remain useful because every assessed row displays
  its observation time, but the word “definitive” applies only to the supplied
  observation set and not to unobserved sellers or future prices.
- An LLM may explain trade-offs but cannot change totals, coverage, or winner
  status.

## Rejected alternatives

- **Missing equals zero:** silently favors incomplete sellers.
- **Subtract coupon badges:** confuses eligibility claims with applied discount.
- **Pick the best comparable row while hiding incomplete rows:** makes a winner
  claim despite an unknown candidate.
- **Use floating point:** creates avoidable rounding and cross-language drift.

## Related

