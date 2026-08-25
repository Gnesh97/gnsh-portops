import type { ApiResult } from '../types/api';
export async function nui<T>(name: string, payload: unknown = {}): Promise<ApiResult<T>> { const r = await fetch(`https://${(window as any).GetParentResourceName?.() ?? 'gnsh-portops'}/${name}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(payload) }); return r.json(); }
