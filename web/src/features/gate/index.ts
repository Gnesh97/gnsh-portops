import { nui } from '../../lib/nui';
import type { ApiResult } from '../../types/api';
export type Appointment = { id: string; status: string; containerId: string };
export const loadAppointments = (filters: Record<string, unknown> = {}): Promise<ApiResult<Appointment[]>> => nui<Appointment[]>('appointments', { filters });
