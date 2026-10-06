# Data Retention & Monthly Archive

**PLANNED / DEFERRED — no archival or purge behavior is implemented.**

Factory Lean should eventually support controlled long-term data management without losing Lean history. An Owner/Admin should explicitly produce and download a monthly archive to the Factory Manager’s device. Safe external/archive storage may be supported later. Browsers must not silently save files to a manager’s device without explicit interaction or permission.

A recent live-data window around 12 months is a candidate for detailed operational records, **not a decided retention period**. Final periods must be configurable and determined separately. Detailed records must be archived before any deletion. Purge must require verified archive success and must never silently delete history. Audit and security-critical records may need longer retention.

Retain important long-term summaries and Lean improvement outcomes, including enough source/evidence history for Before/After, recurrence and trends. Design archive verification, recovery, referential integrity and incomplete-evidence handling before choosing any purge policy.

The current **Export Factory Data** workbook is an application export for human inspection. It is not a restorable database backup or proof that an archive is complete enough to authorize deletion. It performs no purge and schedules no downloads.
