// specs/001 §5.2, 011 §2 — a device is dormant when its most recent activity is more than
// DORMANT_AFTER_DAYS ago, activity = lastSeenAt, else registeredAt (002 §2.4). Presentation
// only; a domain constant, not a plan limit. Pure: no Azure/Google imports.

export const DORMANT_AFTER_DAYS = 30;

const DAY_MS = 24 * 60 * 60 * 1000;

export function isDormant(device: { lastSeenAt?: string; registeredAt: string }, now: Date): boolean {
  const lastActivity = device.lastSeenAt ?? device.registeredAt;
  return now.getTime() - new Date(lastActivity).getTime() > DORMANT_AFTER_DAYS * DAY_MS;
}
