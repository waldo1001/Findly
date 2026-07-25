// specs/002 §2.2 `Users` table — the auth hot path + the group `group:{groupId}` reverse
// index. Integration-tested later; no unit tests here (thin adapter, excluded from mutation).

import { odata, RestError } from "@azure/data-tables";
import { createTableClient } from "./tableClientFactory";
import type { GroupMembershipIndexEntry, GroupRole, Role, UserProfile, UserRepo } from "../../ports/repositories";

const PROFILE_ROW_KEY = "profile";
const GROUP_PREFIX = "group:";

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
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

  async deleteProfile(userId: string): Promise<void> {
    await this.client.deleteEntity(userId, PROFILE_ROW_KEY);
  }

  /** Idempotent (002 §4.2 steps 1/6 — family deletion's re-call needs every step to
   * swallow not-found, same idiom as TableFamilyRepo.removeMember). */
  async clearFamilyMembership(userId: string): Promise<void> {
    try {
      await this.client.updateEntity(
        { partitionKey: userId, rowKey: PROFILE_ROW_KEY, familyId: null, role: null },
        "Merge",
      );
    } catch (err) {
      if (!isNotFound(err)) throw err;
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
    const memberships: GroupMembershipIndexEntry[] = [];
    const entities = this.client.listEntities({
      queryOptions: {
        filter: odata`PartitionKey eq ${userId} and RowKey ge ${GROUP_PREFIX} and RowKey lt ${"group;"}`,
      },
    });
    for await (const entity of entities) {
      memberships.push({
        groupId: String(entity.rowKey).slice(GROUP_PREFIX.length),
        role: entity.role as GroupRole,
        joinedAt: String(entity.joinedAt),
      });
    }
    return memberships;
  }

  async removeGroupMembership(userId: string, groupId: string): Promise<void> {
    try {
      await this.client.deleteEntity(userId, `${GROUP_PREFIX}${groupId}`);
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }
}
