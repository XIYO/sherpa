---
id: RFC-0004
title: Calendar Invitation Authority Boundary
status: draft
owner: maintainer
---

# Calendar Invitation Authority Boundary

## Purpose

Preserve Calendar collaboration as an explicit product plan without implying
that Sherpa can currently edit attendees, send or cancel invitations, or act on
an RSVP. This RFC is a proposal for the authority and safety boundary that must
exist before executable CLI commands or supported capabilities are added.

It does not authorize a write, define a released command, or extend the current
public EventKit Calendar CRUD acceptance claim.

## Current verified boundary

- Event results expose organizer, attendee, role, participant type, and
  participant-status snapshots as untrusted read data.
- Public EventKit exposes the organizer, attendees, and participant properties
  as read-only observations. It provides no attendee-construction or RSVP
  mutation authority for Sherpa's worker.
- Event create and update accept only owner-managed schedule and content
  fields. Strict Rust and Swift input models contain no participant mutation
  field, and unknown participant fields are rejected before EventKit lookup.
- The EventKit worker advertises no invitation capability. `sherpa event`
  exposes only `create`, `update`, and `delete`; those commands never send an
  invitation.

The CLI must not expose a placeholder mutation command that merely fails at
runtime.

## Authority decision required

Implementation must choose and review one real authority before a public
command shape is accepted:

1. an owner-mediated system UI that visibly owns recipient selection and send
   confirmation; or
2. a separately authenticated provider adapter, such as a calendar service API
   whose account, organizer, attendee, invitation, invitation-cancellation, and
   RSVP semantics are documented and testable.

The existing EventKit worker remains the Calendar read and owner-managed CRUD
boundary. A new provider must remain isolated behind an application-owned port
and must not receive Sherpa's database path or inherit Calendar permission as
send authority.

## Required safety contract

Before any executable attendee, invitation, invitation-cancellation, or RSVP
command is registered, the accepted design must define all of the following:

- exact event, calendar, account, organizer, and recurrence-instance authority;
- normalized attendee identity without exposing recipient addresses, names, or
  provider locators in logs, public references, or mutation metadata;
- a full recipient/action preview and an expiring, single-use exact
  confirmation;
- distinct operations for attendee edits, invitation delivery, invitation
  cancellation, and RSVP so one approval cannot authorize another effect;
- journal state written before the external effect and an explicit boundary
  result such as `application_accepted`, `provider_accepted`, or verified
  read-back without claiming delivery when it is unproven;
- exact post-action provider read-back of the event and participant state when
  the selected provider exposes it;
- timeout and uncertain-dispatch handling with no automatic retry after a call
  may have reached the provider;
- recurring-event span, delegation, organizer change, duplicate attendee,
  invitation cancellation, and partial-recipient failure semantics;
- bounded payloads and diagnostics that never contain recipient PII, message
  bodies, access tokens, cookies, or raw provider errors; and
- deterministic fixtures plus an owner-operated controlled-recipient live
  suite before any capability is reported as supported.

## Proposed rollout

1. Verify the chosen provider's supported actions and read-back semantics in a
   non-production spike without adding a public command.
2. Accept a provider-neutral application contract and versioned worker or UI
   boundary.
3. Add exact requirement definitions and matching verification-matrix rows in
   the same change.
4. Add CLI preview-only parsing and deterministic no-dispatch tests.
5. Implement journaled dispatch, uncertain-result handling, and exact read-back.
6. Run the separately confirmed controlled-recipient live suite, then and only
   then advertise the capability as supported.

## Non-goals

- Inferring recipients from Calendar notes, communications, contacts, or model
  output.
- Treating a visible attendee snapshot as permission to contact that person.
- Reusing Context mail or message send confirmation for Calendar invitations.
- Automatic retry, invitation cancellation, RSVP, or series-wide mutation
  after an ambiguous provider result.
- Advertising `disabled` or `supported` merely because EventKit can read an
  organizer or attendee.

## Related

- [Sherpa roadmap](../roadmap/README.md)
- [Planner authority requirements](../requirements/planner-authority.md)
- [System architecture](../architecture/README.md)
- [Worker protocol](../contracts/worker-protocol.md)
- [Owner-operated live evidence](../testing/live-evidence.md)
- Sherpa development boundary rules
- [EventKit event operations](../../apple/eventkit-service/Sources/SherpaEventKitAdapter/event/EventKitEventOperations.swift)
- Calendar domain model
- [Apple EventKit participant documentation](https://developer.apple.com/documentation/eventkit/ekparticipant)
