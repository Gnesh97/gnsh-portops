import { nui } from '../../lib/nui';
import type { ApiResult } from '../../types/api';
export type Overview = { calls: number; moves: number; cranes: number; yard: number; gate: number; customs: number };
export const loadOverview = (): Promise<ApiResult<Overview>> => nui<Overview>('health');
