// specs/002 §2.2 `Users` table — the auth hot path + the group `group:{groupId}` reverse
// index. Integration-tested later; no unit tests here (thin adapter, excluded from mutation).

import { odata, RestError } from "@azure/data-tables";
import { createTableClient } from "./tableClientFactory";
import { collectEntitiesTolerant } from "./listTolerant";
import type { GroupMembershipIndexEntry, GroupRole, Role, UserProfile, UserRepo } from "../../ports/repositories";

const PROFILE_ROW_KEY = "profile";
const GROUP_PREFIX = "group:";
// clearFamilyMembership's guarded-Replace retry budget — same bound as the Usage
// increment loop (002 §2.9, usageTableRepo.ts), the only other read -> guarded-write ->
// bounded-retry idiom in this codebase.
const MAX_RETRIES = 3;

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
}

function isPreconditionFailed(err: unknown): boolean {
  return err instanceof RestError && (err.statusCode === 412 || err.statusCode === 409);
}

export class TableUserRepo implements UserRepo {
  private readonly client = createTableClient("Users");

  async getProfile(userId: string): Promise<UserProfile | null> {
    try {
      const entity = await this.client.getEntity(userId, PROFILE_ROW_KEY);
      return {
        // familyId/role are nullable (family-less users, 001 §1.5 / 002 §2.2) — Table
        // Storage round-trips an explicit `null` property value, so String(null) would
        // wrongly stringify to "null" without this guard.
        familyId: entity.familyId != null ? String(entity.familyId) : null,
        role: entity.role != null ? (entity.role as Role) : null,
        displayName: String(entity.displayName),
      };
    } catch (err) {
      if (isNotFound(err)) return null;
      throw err;
    }
  }

  async createProfile(userId: string, profile: UserProfile): Promise<void> {
    await this.client.createEntity({
      partitionKey: userId,
      rowKey: PROFILE_ROW_KEY,
      familyId: profile.familyId,
      role: profile.role,
      displayName: profile.displayName,
    });
  }

  async updateProfile(userId: string, patch: Partial<UserProfile>): Promise<void> {
    await this.client.updateEntity({ partitionKey: userId, rowKey: PROFILE_ROW_KEY, ...patch }, "Merge");
  }

  /** Idempotent (001 §13.2, 002 §4.2 step 8, B18 — the account-deletion completion marker
   * must converge on a re-call after a prior crashed run already deleted this row, and the
   * §1.5.3 no-profile-caller no-op has nothing to delete at all). */
  async deleteProfile(userId: string): Promise<void> {
    try {
      await this.client.deleteEntity(userId, PROFILE_ROW_KEY);
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }

  /** Idempotent (002 §4.2 steps 1/6 — family deletion's re-call needs every step to
   * swallow not-found, same idiom as TableFamilyRepo.removeMember).
   *
   * B21: Table Storage's Merge has no `null` type — the SDK silently drops null-valued
   * properties from a Merge payload instead of clearing them, so a plain
   * `updateEntity({ familyId: null, role: null }, "Merge")` is a server-side no-op that
   * never actually cleared anything. `Replace` DOES drop omitted properties, but it
   * replaces the *whole* entity with exactly what's given, so it must be seeded with every
   * field that must survive (displayName) and none of the two that must not
   * (familyId/role, simply omitted here).
   *
   * Read -> Replace-with-preserved-displayName, ETag-guarded, bounded retry on conflict —
   * same idiom as the Usage increment loop (002 §2.9) and the sweeper's
   * assertGroupMetaUnchanged ETag-recheck (002 §4.1) — because a concurrent updateProfile
   * (001 §3.5, e.g. a displayName change) could race this read/write pair.
   *
   * If UserProfile ever gains a field beyond familyId/role/displayName, add it to the
   * Replace payload below too — Replace drops anything not explicitly included. */
  async clearFamilyMembership(userId: string): Promise<void> {
    for (let attempt = 0; attempt < MAX_RETRIES; attempt += 1) {
      let entity;
      try {
        entity = await this.client.getEntity(userId, PROFILE_ROW_KEY);
      } catch (err) {
        if (isNotFound(err)) return; // nothing left to clear.
        throw err;
      }

      try {
        await this.client.updateEntity(
          { partitionKey: userId, rowKey: PROFILE_ROW_KEY, displayName: entity.displayName },
          "Replace",
          { etag: entity.etag },
        );
        return;
      } catch (err) {
        // The row got deleted between our read and write (e.g. a concurrent account
        // deletion, or DELETE /families/me/members/{userId}, 001 §3.6) — nothing left to
        // clear, same idempotency contract as the initial read's not-found.
        if (isNotFound(err)) return;
        if (isPreconditionFailed(err) && attempt < MAX_RETRIES - 1) continue;
        // Exhausted retries. Unlike Usage's increment loop (002 §2.9), which is telemetry
        // and deliberately logs-and-drops on exhaustion, clearing family membership is the
        // correctness guarantee 002 §4.2 / 008 §4.2/§5.2 depend on (family deletion and the
        // account-deletion cascade both rely on this actually clearing) — so exhaustion
        // here MUST throw, not silently leave a stale familyId/role in place.
        throw err;
      }
    }
  }

  async addGroupMembership(userId: string, entry: GroupMembershipIndexEntry): Promise<void> {
    await this.client.createEntity({
      partitionKey: userId,
      rowKey: `${GROUP_PREFIX}${entry.groupId}`,
      role: entry.role,
      joinedAt: entry.joinedAt,
    });
  }

  async listGroupMemberships(userId: string): Promise<GroupMembershipIndexEntry[]> {
    // 002 §4.2 (B20) — a Users table that has never been created resolves to no memberships
    // (reachable for account deletion's no-profile-caller bootstrap allowance, 001 §1.5.3).
    const entities = await collectEntitiesTolerant(
      this.client.listEntities({
        queryOptions: {
          filter: odata`PartitionKey eq ${userId} and RowKey ge ${GROUP_PREFIX} and RowKey lt ${"group;"}`,
        },
      }),
    );
    return entities.map((entity) => ({
      groupId: String(entity.rowKey).slice(GROUP_PREFIX.length),
      role: entity.role as GroupRole,
      joinedAt: String(entity.joinedAt),
    }));
  }

  async removeGroupMembership(userId: string, groupId: string): Promise<void> {
    try {
      await this.client.deleteEntity(userId, `${GROUP_PREFIX}${groupId}`);
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }
}
