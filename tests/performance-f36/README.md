# F36 focused verification

`checks.sql` compares the optimized resolver with the original function compiled
from the untouched `20261018073654_production_shift_work_v3_m1.sql` migration into
`pg_temp.f36_original_resolver`. It covers gaps, folds, fractional-hour zones,
historical second offsets, invalid inputs, schedule revisions and immutable facts.
The only occurrence materialization is synthetic and rolled back.

Run only in the exact isolated fixture using the identity-guarded runner:

```powershell
node D:\FactoryLean\Reports\F36-20261115\verify-db.cjs
```

The runner requires the existing isolated QA database on port 29749. Never run
against the owner database or a hosted database. No reset or factory cleanup is
part of the checks. Browser timings, SQL profile and before/after evidence are in
`D:/FactoryLean/Reports/F36-20261115/REPORT.md`.
