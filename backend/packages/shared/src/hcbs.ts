export type HcbsService = {
  code: string;
  description: string;
  unitMinutes: number;
};

export const HCBS_SERVICES: readonly HcbsService[] = [
  { code: 'T1019', description: 'Personal care services, per 15 min', unitMinutes: 15 },
  { code: 'S5125', description: 'Attendant care services, per 15 min', unitMinutes: 15 },
  { code: 'S5126', description: 'Attendant care services, per diem', unitMinutes: 1440 },
  { code: 'T1005', description: 'Respite care services, per 15 min', unitMinutes: 15 },
  { code: 'S5150', description: 'Unskilled respite care, per 15 min', unitMinutes: 15 },
  { code: 'T2025', description: 'Waiver service, per 15 min', unitMinutes: 15 },
  { code: 'S5170', description: 'Home delivered meals, per meal', unitMinutes: 30 },
  { code: 'T1020', description: 'Personal care services, per diem', unitMinutes: 1440 },
] as const;

export function hcbsByCode(code: string): HcbsService | undefined {
  return HCBS_SERVICES.find((s) => s.code === code);
}
