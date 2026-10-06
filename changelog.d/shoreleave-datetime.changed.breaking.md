Shoals date and local-calendar rolls use the Chelis 0.18.13 datetime and
business-calendar operations. This is part of the Std.Datetime cut-over
(shoals#104), not all of it. Fixed-day tenor and regional holiday APIs keep
their existing fixed lists and rules. Shoals also exposes Shoreleave's
published Japan Bank, New South Wales, Hong Kong, TARGET, and NYSE calendars,
which are the source-backed calendars for settlement.

Breaking: `days_in_month` rejects invalid month numbers with a domain error.
A `Calendar` now carries the dates its holiday list covers (`valid_from`,
`valid_until`), so a `Calendar { .. }` literal names both. Business-day
queries, rolls, and offsets on a local calendar fail outside that coverage:
the 2025 lists answer only for 2025, the year constructors for their year,
and the multi-year constructors for an unbroken run of years, rejecting an
empty or gapped year list. `as_business_calendar` gives the adapted calendar
that horizon. `add_business_days` steps backward for a negative count, and
zero business days from a non-business start returns the following business
day.

Still open under shoals#104: deleting the local holiday tables and
`is_weekend`; a Tenor built on Period, with ON/TN/SN as business-day lag and
length, and anchored schedules; and exact-rational day counts with
unambiguous names and their required extra inputs.
