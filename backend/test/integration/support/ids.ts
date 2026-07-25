import { randomUUID } from "node:crypto";

/** A fresh familyId per test so concurrent/parallel test files never collide on shared
 * Azurite state (tables are partitioned by familyId; blob paths are prefixed by it). */
export function testFamilyId(): string {
  return `fam_test_${randomUUID().replace(/-/g, "").slice(0, 16)}`;
}

export function testUserId(): string {
  return `user_test_${randomUUID().replace(/-/g, "").slice(0, 12)}`;
}

export function testDeviceId(): string {
  return randomUUID();
}

export function testGroupId(): string {
  return `grp_test_${randomUUID().replace(/-/g, "").slice(0, 12)}`;
}

/** `lr_` + 20 chars `[A-Za-z0-9]` (specs/001 §1.4 ID format). */
export function testRequestId(): string {
  return `lr_${randomUUID().replace(/-/g, "").slice(0, 20)}`;
}
