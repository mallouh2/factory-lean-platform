# Existing database migration mapping

Checked through the connected Supabase integration on 2026-09-16. The integration records execution timestamps; file names retain their original source versions. Every applied change has a committed SQL file.

| Source migration | Development recorded version | Testing recorded version |
|---|---|---|
| 20260915100155_phase_one_foundation | 20260915121813 | 20260915155830 |
| 20260915121815_phase_one_operations | 20260915122019 | 20260915155843 |
| 20260915122053_phase_one_completion | 20260915122442 | 20260915155859 |
| 20260915140100_operation_controls | 20260915160127 | 20260915160143 |
| 20260915162000_operational_integrity | 20260915161617 | 20260915161601 |
| 20260915165000_work_center_configuration | 20260915162936 | 20260915162915 |

| 20260916120000_personal_access_and_production_flow | 20260916130933 | 20260916124218 |
| 20260916123000_configurable_stop_impact_scope | 20260916131006 | 20260916124830 |
| 20260916130000_flow_configuration_integrity | 20260916131024 | 20260916125155 |
| 20260916133000_transfer_interruption_history | 20260916131043 | 20260916130018 |

Do not reapply these files to existing projects. New installations apply source files in order. Before adopting CLI push for an existing project, compare schema and migration statements, then reconcile history in a documented maintenance operation. No migration history repair was performed here.

`supabase/proposals/audited_support_reads.sql` is **not applied** and is not part of setup. Its broad policy rollout was rejected by automatic review. The user subsequently deferred detailed security work until feature completion.
