# Snapshot loading inventory

Measured before edits on TESTING, 2026-10-01, as the existing authenticated account. SQL JSONB text: **7,588,943 bytes**. This is not the compact HTTP response size. Every section is factory/RLS scoped; row counts reflect this user's visibility.

| Section | Rows | Bytes | Active consumers | Initial operational need | Delivery decision |
| --- | ---: | ---: | --- | --- | --- |
| areas | 8 | 1917 | Configuration, DowntimeAnalysis, Reports, Floor drawers | Yes; identity, authorization or configuration | Retain unchanged |
| audit_logs | 5000 | 2337307 | Administration → AuditHistory (only Audit) | No; historical review only | Lazy, page-specific |
| daily_targets | 4 | 1176 | Legacy command/API contract tests (no active UI consumer) | No current screen; small compatibility contract | Retain unchanged |
| downtime_classification_corrections | 0 | 2 | LossImpactReview selected event + calibration observations | No; historical review only | Lazy, page-specific |
| downtime_events | 29 | 34791 | DashboardFlow, FactoryFloorV2, CenterDetails, DowntimeCapture, DowntimeAnalysis, Reports, LossImpactReview | Mixed: current operations and existing historical consumers | Retain unchanged; keep local truncation warning at existing historical consumer |
| downtime_reasons | 16 | 4290 | Floor stop actions, DowntimeCapture, Loss Review, Configuration, Reports | Yes; identity, authorization or configuration | Retain unchanged |
| machine_statuses | 5 | 586 | Machine state controls, Configuration; static catalog | Yes; identity, authorization or configuration | Retain unchanged |
| memberships | 5 | 2140 | Administration, PersonPermissions, Recording technician identity, history actor display | Yes; identity, authorization or configuration | Retain unchanged |
| oee_observations | 0 | 2 | Reports utilization/daily summary | Mixed: current operations and existing historical consumers | Retain unchanged; keep local truncation warning at existing historical consumer |
| operator_assignments | 12 | 4044 | Legacy command/API contract tests (no active UI consumer) | No current screen; small compatibility contract | Retain unchanged |
| permissions | 78 | 3351 | PersonPermissions, Administration, testingPreviewEligible catalog | Yes; identity, authorization or configuration | Retain unchanged |
| production_entries | 5 | 3618 | Floor/Dashboard today output, Orders recent entries, Reports; full ProductionHistory already lazy | Mixed: current operations and existing historical consumers | Retain unchanged; keep local truncation warning at existing historical consumer |
| production_lines | 7 | 2399 | Floor, Planning, Orders, Recording, Configuration, Reports | Yes; identity, authorization or configuration | Retain unchanged |
| production_loss_actuals | 2 | 976 | LossImpactReview selected event + calibration observations | No; historical review only | Lazy, page-specific |
| production_loss_context_snapshots | 148 | 4998182 | LossImpactReview calculation only | No; historical review only | Lazy, page-specific |
| production_loss_estimates | 0 | 2 | LossImpactReview immutable recorded result + observations | No; historical review only | Lazy, page-specific |
| production_loss_profiles | 0 | 2 | CenterLossProfile configuration; Loss Review calibration actions | Yes; identity, authorization or configuration | Retain unchanged |
| production_loss_recovery_rates | 0 | 2 | CenterLossProfile configuration | Yes; identity, authorization or configuration | Retain unchanged |
| production_orders | 14 | 10646 | Floor current/queue, Planning, Orders, Recording, Dashboard, Reports, CenterDetails | Yes; identity, authorization or configuration | Retain unchanged |
| production_requests | 13 | 4733 | Orders, Planning, Floor request identity, Recording | Yes; identity, authorization or configuration | Retain unchanged |
| production_routing_steps | 0 | 2 | No active snapshot UI reader; context builder reads SQL directly, retained compatibility | No current screen; small compatibility contract | Retain unchanged |
| production_transfers | 12 | 7793 | evaluateFlow / Floor / Dashboard, CenterDetails, ProductionTransfers, DowntimeAnalysis | Mixed: current operations and existing historical consumers | Retain unchanged; keep local truncation warning at existing historical consumer |
| products | 5 | 1911 | Orders, Planning, Floor, Recording, Configuration, CenterLossProfile | Yes; identity, authorization or configuration | Retain unchanged |
| role_permissions | 116 | 17104 | PersonPermissions grant templates, Administration | Yes; identity, authorization or configuration | Retain unchanged |
| roles | 16 | 3473 | Administration, PersonPermissions | Yes; identity, authorization or configuration | Retain unchanged |
| status_events | 153 | 54059 | CenterDetails recent history, Reports activity/utilization | Mixed: current operations and existing historical consumers | Retain unchanged; keep local truncation warning at existing historical consumer |
| support_access | 1 | 294 | Administration support grants, snapshot authorization metadata | Yes; identity, authorization or configuration | Retain unchanged |
| user_permissions | 319 | 72097 | PersonPermissions, Administration | Yes; identity, authorization or configuration | Retain unchanged |
| work_center_alternatives | 4 | 688 | Floor transfer picker/branches, CenterAlternatives, Configuration | Yes; identity, authorization or configuration | Retain unchanged |
| work_center_capabilities | 6 | 1341 | Planning, transfer eligibility, CenterCapabilities/CenterLossProfile, Configuration | Yes; identity, authorization or configuration | Retain unchanged |
| work_center_categories | 14 | 3449 | Floor machine identity, Configuration, CenterAlternatives, CenterCapabilities | Yes; identity, authorization or configuration | Retain unchanged |
| work_centers | 13 | 13234 | evaluateFlow, all Floor/config/Planning/Recording/report/history identities | Yes; identity, authorization or configuration | Retain unchanged |

## Metadata and API hydration

- `factory`, `membership`, `user`, `permissions` access matrix, `platformAdmin`, `factories`, `supportFactories`, `testingPreviewEligible`, `fetchedAt`: FactoryApp, auth/navigation, FeatureProps and permission previews; retained unchanged.
- `truncatedTables`: only retained bounded snapshot sections; Audit and Loss Review use real pagination.
- `production_recording_units` / `production_technicians`: current authorized RPC-derived Recording eligibility and technician choices; retained in GET /api/data, not the SQL snapshot.
- `production_shifts`: Recording choices, Administration ProductionShifts; current factory-scoped hydration retained. None configured in this TESTING baseline.
- `production_plan_revisions` / `production_entry_corrections` are not global snapshot sections. Existing Planning detail / Production History queries remain unchanged.

## Decisions

Audit and all historical loss review inputs move together so no consumer silently reads missing arrays. Loss profiles/recovery rates stay available for configuration. Loss detail uses the unchanged JS model on the server, fetching bounded event-specific context pages and comparable observations for the same machine across all authorized historical pages; it never sends raw full-factory contexts to React. No date/sample cap is introduced into calibration.

Downtime/status/output/transfer histories are small here but have active mixed current/report consumers. Replacing them with only open/today rows would change existing reports; leave those sections and their scoped limit warnings intact in this refactor. Their eventual report-specific separation requires its own consumer migration. Three small legacy compatibility sections are retained to avoid removing external command contract coverage; they contribute about 5.2 KB combined.
