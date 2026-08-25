import { nui } from '../../lib/nui';
import type { ApiResult } from '../../types/api';
export type CraneHealth = { ready: boolean; stage?: string; version?: string };
export const loadCraneBoard = (): Promise<ApiResult<CraneHealth>> => nui<CraneHealth>('health');
