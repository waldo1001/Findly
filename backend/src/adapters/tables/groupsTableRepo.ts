// specs/002 §2.10 `Groups` table. Integration-tested later against Azurite; no unit tests
// here (thin adapter, excluded from mutation).

import { odata, RestError } from "@azure/data-tables";
import { createTableClient } from "./tableClientFactory";
import { collectEntitiesTolerant } from "./listTolerant";
import type {
  GroupExpiryPolicy,
  GroupMember,
  GroupMeta,
  GroupMetaAssertOutcome,
  GroupRepo,
  GroupRole,
} from "../../ports/repositories";

const META_ROW_KEY = "meta";
const MEMBER_PREFIX = "member:";

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
}

function isPreconditionFailed(err: unknown): boolean {
  return err instanceof RestError && (err.statusCode === 412 || err.statusCode === 409);
}

export class TableGroupRepo implements GroupRepo {
  private readonly client = createTableClient("Groups");

  async createGroupMeta(meta: GroupMeta): Promise<void> {
    await this.client.createEntity({
      partitionKey: meta.groupId,
      rowKey: META_ROW_KEY,
      name: meta.name,
      ownerUserId: meta.ownerUserId,
      createdAt: meta.createdAt,
      endsAt: meta.endsAt,
      expiryPolicy: meta.expiryPolicy,
      code: meta.code,
    });
  }

  async getGroupMeta(groupId: string): Promise<GroupMeta | null> {
    try {
      const entity = await this.client.getEntity(groupId, META_ROW_KEY);
      return {
        groupId,
        name: String(entity.name),
        ownerUserId: String(entity.ownerUserId),
        createdAt: String(entity.createdAt),
        endsAt: String(entity.endsAt),
        expiryPolicy: entity.expiryPolicy as GroupExpiryPolicy,
        code: String(entity.code),
        etag: entity.etag,
      };
    } catch (err) {
      if (isNotFound(err)) return null;
      throw err;
    }
  }

  async addMember(groupId: string, member: GroupMember): Promise<void> {
    await this.client.createEntity({
      partitionKey: groupId,
      rowKey: `${MEMBER_PREFIX}${member.userId}`,
      role: member.role,
      displayName: member.displayName,
      joinedAt: member.joinedAt,
    });
  }

  async listMembers(groupId: string): Promise<GroupMember[]> {
    // 002 §4.2 (B20) — a Groups table that has never been created resolves to no members.
    const entities = await collectEntitiesTolerant(
      this.client.listEntities({
        queryOptions: {
          filter: odata`PartitionKey eq ${groupId} and RowKey ge ${MEMBER_PREFIX} and RowKey lt ${"member;"}`,
        },
      }),
    );
    return entities.map((entity) => ({
      userId: String(entity.rowKey).slice(MEMBER_PREFIX.length),
      role: entity.role as GroupRole,
      displayName: String(entity.displayName),
      joinedAt: String(entity.joinedAt),
    }));
  }

  async getMember(groupId: string, userId: string): Promise<GroupMember | null> {
    try {
      const entity = await this.client.getEntity(groupId, `${MEMBER_PREFIX}${userId}`);
      return {
        userId,
        role: entity.role as GroupRole,
        displayName: String(entity.displayName),
        joinedAt: String(entity.joinedAt),
      };
    } catch (err) {
      if (isNotFound(err)) return null;
      throw err;
    }
  }

  async updateGroupMeta(
    groupId: string,
    patch: Partial<Pick<GroupMeta, "name" | "endsAt" | "code">>,
  ): Promise<GroupMeta> {
    await this.client.updateEntity({ partitionKey: groupId, rowKey: META_ROW_KEY, ...patch }, "Merge");
    const entity = await this.client.getEntity(groupId, META_ROW_KEY);
    return {
      groupId,
      name: String(entity.name),
      ownerUserId: String(entity.ownerUserId),
      createdAt: String(entity.createdAt),
      endsAt: String(entity.endsAt),
      expiryPolicy: entity.expiryPolicy as GroupExpiryPolicy,
      code: String(entity.code),
    };
  }

  async deleteGroupMeta(groupId: string): Promise<void> {
    try {
      await this.client.deleteEntity(groupId, META_ROW_KEY);
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }

  async removeMember(groupId: string, userId: string): Promise<void> {
    try {
      await this.client.deleteEntity(groupId, `${MEMBER_PREFIX}${userId}`);
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }

  async assertGroupMetaUnchanged(groupId: string, etag: string): Promise<GroupMetaAssertOutcome> {
    try {
      // A no-op merge (no properties beyond the key) — the ETag precondition is still
      // enforced server-side even though nothing is actually changed. B12 security fix
      // (002 §4.1 TOCTOU): the sweeper calls this immediately before any destructive action.
      await this.client.updateEntity({ partitionKey: groupId, rowKey: META_ROW_KEY }, "Merge", { etag });
      return "ok";
    } catch (err) {
      // Both "changed" (412/409) and "gone entirely" (404 — e.g. the owner's own DELETE raced
      // in first) mean the caller's snapshot is stale; either way it's a conflict, not a throw.
      if (isPreconditionFailed(err) || isNotFound(err)) return "conflict";
      throw err;
    }
  }
}
