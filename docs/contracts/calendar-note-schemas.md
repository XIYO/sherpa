# Calendar note schemas

Calendar notes can be durable, versioned records.  A note schema is not the
Planner worker protocol and it is not a generic JSON Schema.  It is the
writing and update format that Sherpa uses for one kind of accumulated Calendar
data.

The marker is the final non-blank line of the note:

```text
@schema: xiyo.calendar.card-payment@2.2
```

The Swift registry in
[`CalendarNoteSchemas.swift`](../../apple/eventkit-service/Sources/SherpaPlannerContract/CalendarNoteSchemas.swift)
is the implementation source of truth.  It currently recognizes the two
versions observed in the Calendar.

| Schema | Writing checklist |
| --- | --- |
| `xiyo.calendar.card-payment@2.1` | 카드, 결제, 보안, 기본혜택, 프로모션, 자동납부 |
| `xiyo.calendar.card-payment@2.2` | 카드, 결제, 명세서, 보안, 기본혜택, 프로모션, 자동납부 |

Each entry's exact ordered fields are in the Swift registry.  The notable
`2.2` additions are `결제계좌`, `명세서/수신처`, `기본혜택/실적포함`, and
`기본혜택/포인트표`; `2.1` does not require them.

## Update rules

- Keep the existing schema version when updating a record.
- Use `xiyo.calendar.card-payment@2.2` for a new card-payment record.
- A released version is immutable.  Add a new version when the writing
  checklist, field meaning, section structure, or representation needs to
  change; do not silently redefine an old version.
- Fixing a typo or adding a newly learned fact to a record is an ordinary
  update, not a schema version change.
- Migration between versions is a separate, explicit operation with a preview;
  it is never performed as a side effect of reading or updating a record.
- Preserve unknown sections and facts when updating a known record.
- Follow the version's ordered field checklist while writing.  A field may be
  omitted only when the source has no fact and `확인 필요` would not be true.
- Preserve the entire note when its schema version is unknown or its marker is
  malformed; do not guess a migration or overwrite it.
- Ordinary Calendar notes and all Reminder notes remain free text unless they
  explicitly introduce their own schema marker and registry entry.

## Related

- [Planner authority requirements](../requirements/planner-authority.md)
