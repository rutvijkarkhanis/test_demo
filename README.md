# KC Project Leads — Command Dashboard

An interactive, self-contained HTML dashboard built from the **KC PROJECT LEADS**
project-management workbook. No backend and no build step — all data is embedded
directly in `index.html`, so it runs by opening the file in any browser.

## Open it

Open `index.html` in a browser (double-click, or serve the folder with any static
host). Everything is inline; there are no external dependencies except web fonts,
which fall back gracefully offline.

## What it shows

| Section | Contents |
| --- | --- |
| **Projects** | The 3 formal projects (KC-001/002/003) with the full stage-intelligence layer — Actual, Projected and Material-Inferred stages plotted on the 13-stage construction rail, plus a confidence rating and next action. |
| **Follow-up Calendar** | A live feed consolidated from project stage timing, BOQ requirement dates, field visits and discussions — grouped Overdue / This Week / This Month / Later, filterable by project, priority and action type. |
| **Materials / BOQ** | 17 BOQ lead groups (249 line items) with brand-engagement status, KC score, mapped stage, and expandable sub-items. |
| **Field Leads** | All 112 site visits, filterable by visit status, interest level and field executive. |
| **Discussions** | 64 architect / designer / visitor discussions logged by the concierge team. |
| **Unlinked Leads** | Field and discussion records not yet tied to a formal project, needing verification before a Project ID is assigned. |
| **Legend** | Reading guide for stage confidence, rail markers (A / P / M), action types and priorities. |

## Key stats (as of 20 Aug 2026)

- 3 formal projects (2 active, 1 lead)
- 112 field site visits · 24 hot leads
- 249 BOQ material items across 17 lead groups
- 64 project discussions
- 176 unlinked leads awaiting project assignment

## Design notes

- **Mobile-friendly**, responsive layout with light/dark themes (respects the OS
  preference and offers a manual toggle).
- Search and multi-filter controls on every data-heavy section.
- Read-only view. **Actual Stage is the field-verified truth**; Projected and
  Material-Inferred stages are planning/diagnostic signals, not reality.

## Regenerating the data

`index.html` embeds a trimmed JSON snapshot of the workbook under
`window.KC_DATA`. To refresh it, re-export the sheets to JSON and re-inject that
payload into the `<script>window.KC_DATA=…</script>` block.
