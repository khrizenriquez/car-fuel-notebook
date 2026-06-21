# ADR-004: Analytics Allocation Rules

## Status
Accepted

## Context
Tank cycles can span month boundaries, and the user wants both simple and more precise monthly analysis.

## Decision
Use the month of the closing fill-up as the default monthly allocation rule. Also provide an alternate prorated view that splits tank cycles across months proportionally by time interval.

## Rejected Alternatives
- Final-fill month only: simple but hides cross-month behavior.
- Prorated only: precise but harder to explain and verify quickly.
- Manual allocation per tank: too much user effort.

## Consequences
- Dashboard home remains easy to understand.
- Advanced view offers a more faithful month-by-month comparison.
- Analytics engine must support two allocation strategies.

## Deferred Work
- Mileage allocation using snapshots instead of date-based proration.
- More detailed per-week analytics.
