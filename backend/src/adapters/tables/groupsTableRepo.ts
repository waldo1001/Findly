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
// updateGroupMeta's guarded-Replace retry budget when clearing endsAt (same bound and idiom as
// usersTableRepo.clearFamilyMembership / the Usage increment loop).
const MAX_RETRIES = 3;

// `endsAt` is nullable (002 §2.10, 005 §2.5) and Table Storage has no null type: a null is
// stored as an ABSENT property, so an absent/null value reads back as `null`.
function readEndsAt(entity: Record<string, unknown>): string | null {
  return entity.endsAt != null ? String(entity.endsAt) : null;
}

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
      // Omit the property for a group without an end date — never write an explicit null.
      ...(meta.endsAt !== null ? { endsAt: meta.endsAt } : {}),
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
        endsAt: readEndsAt(entity),
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
    if (patch.endsAt === null) {
      await this.clearEndsAt(groupId, patch);
    } else {
      await this.client.updateEntity({ partitionKey: groupId, rowKey: META_ROW_KEY, ...patch }, "Merge");
    }
    const entity = await this.client.getEntity(groupId, META_ROW_KEY);
    return {
      groupId,
      name: String(entity.name),
      ownerUserId: String(entity.ownerUserId),
      createdAt: String(entity.createdAt),
      endsAt: readEndsAt(entity),
      expiryPolicy: entity.expiryPolicy as GroupExpiryPolicy,
      code: String(entity.code),
    };
  }

  /**
   * Removes the end date. A Merge cannot do this: the SDK drops null-valued properties from the
   * payload, so the old date would silently survive (the B21 trap). Instead: read, then an
   * ETag-guarded Replace carrying every column except `endsAt` (plus any name/code in the same
   * patch), retried on a concurrent write. If the Groups meta schema ever gains a column, add
   * it to the Replace payload here too — Replace drops anything not explicitly included.
   */
  private async clearEndsAt(
    groupId: string,
    patch: Partial<Pick<GroupMeta, "name" | "endsAt" | "code">>,
  ): Promise<void> {
    for (let attempt = 0; attempt < MAX_RETRIES; attempt += 1) {
      const entity = await this.client.getEntity(groupId, META_ROW_KEY);
      try {
        await this.client.updateEntity(
          {
            partitionKey: groupId,
            rowKey: META_ROW_KEY,
            name: patch.name ?? String(entity.name),
            ownerUserId: String(entity.ownerUserId),
            createdAt: String(entity.createdAt),
            expiryPolicy: entity.expiryPolicy as GroupExpiryPolicy,
            code: patch.code ?? String(entity.code),
          },
          "Replace",
          { etag: entity.etag },
        );
        return;
      } catch (err) {
        if (isPreconditionFailed(err) && attempt < MAX_RETRIES - 1) continue;
        throw err; // exhausted (or not found): the caller asked for an owner-visible change.
      }
    }
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
