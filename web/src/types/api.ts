export type ApiResult<T> = { ok: true; data: T; meta?: Record<string, unknown> } | { ok: false; error: { code: string; message: string } };
