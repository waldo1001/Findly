// specs/002 §2.1 `Families` table. Integration-tested later against Azurite; no unit
// tests here (thin adapter, excluded from mutation).

import { odata, RestError } from "@azure/data-tables";
import { createTableClient } from "./tableClientFactory";
import { collectEntitiesTolerant } from "./listTolerant";
import type { FamilyInviteIndexEntry, FamilyMember, FamilyMeta, FamilyRepo, Role } from "../../ports/repositories";

const META_ROW_KEY = "meta";
const MEMBER_PREFIX = "member:";
const INVITE_INDEX_PREFIX = "invite:";

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
}

export class TableFamilyRepo implements FamilyRepo {
  private readonly client = createTableClient("Families");

  async createFamily(meta: FamilyMeta): Promise<void> {
    await this.client.createEntity({
      partitionKey: meta.familyId,
      rowKey: META_ROW_KEY,
      familyName: meta.familyName,
      createdBy: meta.createdBy,
      createdAt: meta.createdAt,
    });
  }

  async getFamilyMeta(familyId: string): Promise<FamilyMeta | null> {
    try {
      const entity = await this.client.getEntity(familyId, META_ROW_KEY);
      return {
        familyId,
        familyName: String(entity.familyName),
        createdBy: String(entity.createdBy),
        createdAt: String(entity.createdAt),
      };
    } catch (err) {
      if (isNotFound(err)) return null;
      throw err;
    }
  }

  async addMember(familyId: string, member: FamilyMember): Promise<void> {
    await this.client.createEntity({
      partitionKey: familyId,
      rowKey: `${MEMBER_PREFIX}${member.userId}`,
      role: member.role,
      displayName: member.displayName,
      joinedAt: member.joinedAt,
    });
  }

  async listMembers(familyId: string): Promise<FamilyMember[]> {
    // 002 §4.2 (B20) — a Families table that has never been created resolves to no members.
    const entities = await collectEntitiesTolerant(
      this.client.listEntities({
        queryOptions: {
          filter: odata`PartitionKey eq ${familyId} and RowKey ge ${MEMBER_PREFIX} and RowKey lt ${"member;"}`,
        },
      }),
    );
    return entities.map((entity) => ({
      userId: String(entity.rowKey).slice(MEMBER_PREFIX.length),
      role: entity.role as Role,
      displayName: String(entity.displayName),
      joinedAt: String(entity.joinedAt),
    }));
  }

  async updateMember(
    familyId: string,
    userId: string,
    patch: Partial<Pick<FamilyMember, "role" | "displayName">>,
  ): Promise<FamilyMember> {
    const rowKey = `${MEMBER_PREFIX}${userId}`;
    await this.client.updateEntity({ partitionKey: familyId, rowKey, ...patch }, "Merge");
    const entity = await this.client.getEntity(familyId, rowKey);
    return {
      userId,
      role: entity.role as Role,
      displayName: String(entity.displayName),
      joinedAt: String(entity.joinedAt),
    };
  }

  /** Idempotent (002 §4.2 — family deletion's re-call needs every delete to swallow
   * not-found, same idiom as TableGroupRepo.removeMember). */
  async removeMember(familyId: string, userId: string): Promise<void> {
    try {
      await this.client.deleteEntity(familyId, `${MEMBER_PREFIX}${userId}`);
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }

  async addInviteIndexEntry(familyId: string, entry: FamilyInviteIndexEntry): Promise<void> {
    await this.client.createEntity({
      partitionKey: familyId,
      rowKey: `${INVITE_INDEX_PREFIX}${entry.code}`,
      expiresAt: entry.expiresAt,
    });
  }

  async listInviteIndexEntries(familyId: string): Promise<FamilyInviteIndexEntry[]> {
    // 002 §4.2 (B20) — same tolerance as listMembers: no table yet means no entries.
    const entities = await collectEntitiesTolerant(
      this.client.listEntities({
        queryOptions: {
          filter: odata`PartitionKey eq ${familyId} and RowKey ge ${INVITE_INDEX_PREFIX} and RowKey lt ${"invite;"}`,
        },
      }),
    );
    return entities.map((entity) => ({
      code: String(entity.rowKey).slice(INVITE_INDEX_PREFIX.length),
      expiresAt: String(entity.expiresAt),
    }));
  }

  async removeInviteIndexEntry(familyId: string, code: string): Promise<void> {
    try {
      await this.client.deleteEntity(familyId, `${INVITE_INDEX_PREFIX}${code}`);
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }

  async deleteFamilyMeta(familyId: string): Promise<void> {
    try {
      await this.client.deleteEntity(familyId, META_ROW_KEY);
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }
}
