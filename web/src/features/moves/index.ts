import { nui } from '../../lib/nui';
import type { ApiResult } from '../../types/api';
export type MoveRow = { id: string; status: string; containerId: string; version: number };
export const loadMoves = (filters: Record<string, unknown> = {}): Promise<ApiResult<MoveRow[]>> => nui<MoveRow[]>('moves', { filters });
