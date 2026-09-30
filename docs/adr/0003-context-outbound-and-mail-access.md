---
id: ADR-0003
title: Approval-Gated Context Outbound and Hybrid Mail Access
status: accepted
owner: maintainer
---

# ADR-0003: Approval-Gated Context Outbound and Hybrid Mail Access

## Context

Sherpa must read and write KakaoTalk, iMessage/SMS/RCS, and mail while keeping
the LLM outside privileged execution. The three macOS integrations expose
different boundaries:

- Agent Messenger reads and sends KakaoTalk through an authenticated LOCO tablet session.
- `imsg` reads the local Messages database and asks Messages.app to send.
- Mail.app already aggregates the owner's configured accounts and exposes read
  and send commands through Apple events.

IMAP and SMTP are useful direct mail protocols, but they do not reuse Mail.app's
stored account credentials. IMAP covers reads and mailbox-state mutations;
SMTP covers submission. Each direct account therefore needs its own OAuth or
app-password configuration.

None of the current sender boundaries supplies a trustworthy provider delivery
or recipient-read receipt for the command Sherpa executes.

## Decision

Context collection and outbound are separate application capabilities. All
collection and LLM analysis paths remain read-only. An outbound operation uses
this two-phase workflow:

1. Accept the body on bounded UTF-8 stdin and validate the safe target or exact
   mail headers.
2. Persist an immutable expiring draft and render its full preview plus a random
   one-time confirmation code.
3. Atomically consume the exact draft/code pair.
4. Resolve a safe `K...` or `I...` thread alias to its native target inside the
   protected Context store.
5. Journal and dispatch one versioned `write_with_verification` worker request.
6. Persist `accepted`, `failed`, or `partial` with safe operation metadata.

Native locators never enter the public draft, approval store, renderer, or
mutation metadata. KakaoTalk uses an exact authenticated account and chat ID.
Messages must return the exact requested chat ID before send.

Inbound KakaoTalk photos are part of the conversation evidence. Context stores
each image from Agent Messenger's presigned attachment URL in an owner-only,
source-neutral media directory. Paths use opaque hashes rather than native
account, room, or message identifiers. Image download and analysis must finish
before the room checkpoint advances; a missing or expired image URL leaves the
page incomplete. The source URL itself is not retained.

The first mail implementation is the Mail.app aggregate adapter. It reads the
already configured enabled accounts and sends only through an exact configured
sender; an optional account selector must also match exactly. It never extracts
or exports account credentials.

A direct IMAP/SMTP implementation is a later, independent adapter. It is added
per account only when direct server access provides a concrete benefit. It does
not replace the aggregate adapter or change the application-owned mail port.

Current outbound success is named `application_accepted`. It is not delivery,
receipt, or read verification. A timeout or failure after native invocation is
`dispatch_uncertain` and receives no automatic retry because a retry can create
a duplicate message.

Development remains unsigned-first. Rebuilt executables may require macOS
privacy authorization again; that does not change the application contract.

## Consequences

- One public `sherpa context send` interface covers all three channels while
  native tools remain isolated and replaceable.
- Existing Mail.app accounts work without duplicating provider setup.
- Direct mail remains possible without making credentials part of canonical
  state or coupling the domain to IMAP/SMTP libraries.
- Approval storage and the mutation journal retain message bodies only where
  the explicit draft requires them; logs and mutation metadata remain content
  free.
- Provider ambiguity, missing adapters, authorization, and uncertain dispatch
  are explicit failures rather than fallback target selection or silent retry.

## Rejected alternatives

- **Let the LLM call native senders:** bypasses deterministic approval,
  validation, target resolution, and journaling.
- **Use only direct IMAP/SMTP immediately:** duplicates setup for every account
  already configured in Mail.app and still does not cover Messages or KakaoTalk.
- **Read credentials from Mail.app:** no supported credential-export contract
  exists and it would expand Sherpa's secret-handling boundary.
- **Treat process success as delivery:** states stronger evidence than the
  adapters actually observe.
- **Retry every send failure:** can duplicate a message after an uncertain
  native acceptance.

## Related

- [System architecture](../architecture/README.md)
- [Context requirements](../requirements/context-intelligence.md)
- [Worker protocol](../contracts/worker-protocol.md)
- [Roadmap](../roadmap/README.md)
- [Test strategy](../testing/README.md)
