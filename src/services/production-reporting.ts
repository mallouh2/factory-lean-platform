import type { authenticatedClient } from './authorization';
import { reportingResponse } from '@/utils/production-reporting.mjs';

type Client = Awaited<ReturnType<typeof authenticatedClient>>['db'];
type Arguments = Parameters<typeof reportingResponse>[1];

// One bounded protected SQL call; never supplement V3 with legacy numeric rows.
export async function readProductionReporting(db: Client, args: Arguments) {
  const { data, error } = await db.rpc('production_history',
    { ...args, filters: JSON.stringify(args.filters) }, { get: true });
  if (error) throw error;
  return reportingResponse(data, args);
}
