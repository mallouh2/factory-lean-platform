import type { authenticatedClient } from './authorization';
type Client = Awaited<ReturnType<typeof authenticatedClient>>['db'];

// The on-screen history and export must use the same protected reader and KG supplements.
export async function readProductionHistory(db: Client, factory: string, args: Record<string, unknown>) {
  const { data, error } = await db.rpc('production_history', { factory, ...args });
  if (error) throw error;
  if (data?.rows?.length) {
    const { data: mass, error: massError } = await db.from('production_entries')
      .select('id,effective_scrap_kg,effective_startup_kg,lean_startup_id,produced_weight_kg,weight_kg_per_unit')
      .eq('factory_id', factory).in('id', data.rows.map((x: { id: string }) => x.id));
    if (massError) throw massError;
    data.rows = data.rows.map((x: { id: string }) => ({ ...x, ...mass?.find(y => y.id === x.id) }));
  }
  return data;
}
