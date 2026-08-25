import { nui } from '../../lib/nui';
import type { ApiResult } from '../../types/api';
export type YardRow = { id: string; state: string; zone: string; version: number };
export const loadYard = (filters: Record<string, unknown> = {}): Promise<ApiResult<YardRow[]>> => nui<YardRow[]>('yard', { filters });
