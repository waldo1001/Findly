// specs/002 §2.3 `Invites` table. Integration-tested later; no unit tests here (thin
// adapter, excluded from mutation).

import { RestError } from "@azure/data-tables";
import { createTableClient } from "./tableClientFactory";
import type { ConsumeInviteResult, InviteRecord, InviteRepo, Role } from "../../ports/repositories";

const INVITE_ROW_KEY = "invite";

function isNotFound(err: unknown): boolean {
  return err instanceof RestError && err.statusCode === 404;
}

function isPreconditionFailed(err: unknown): boolean {
  return err instanceof RestError && (err.statusCode === 412 || err.statusCode === 409);
}

export class TableInviteRepo implements InviteRepo {
  private readonly client = createTableClient("Invites");

  async createInvite(invite: InviteRecord): Promise<void> {
    await this.client.createEntity({
      partitionKey: invite.inviteCode,
      rowKey: INVITE_ROW_KEY,
      familyId: invite.familyId,
      role: invite.role,
      emailHint: invite.emailHint ?? null,
      createdBy: invite.createdBy,
      createdAt: invite.createdAt,
      expiresAt: invite.expiresAt,
      usedBy: null,
      usedAt: null,
    });
  }

  async getInvite(inviteCode: string): Promise<InviteRecord | null> {
    try {
      const entity = await this.client.getEntity(inviteCode, INVITE_ROW_KEY);
      return {
        inviteCode,
        familyId: String(entity.familyId),
        role: entity.role as Role,
        emailHint: entity.emailHint != null ? String(entity.emailHint) : undefined,
        createdBy: String(entity.createdBy),
        createdAt: String(entity.createdAt),
        expiresAt: String(entity.expiresAt),
        usedBy: entity.usedBy != null ? String(entity.usedBy) : undefined,
        usedAt: entity.usedAt != null ? String(entity.usedAt) : undefined,
      };
    } catch (err) {
      if (isNotFound(err)) return null;
      throw err;
    }
  }

  /** ETag-guarded merge (002 §2.3) — the precondition failure maps to "alreadyUsed". */
  async consumeInvite(inviteCode: string, usedBy: string, usedAt: string): Promise<ConsumeInviteResult> {
    const entity = await this.client.getEntity(inviteCode, INVITE_ROW_KEY);
    if (entity.usedBy != null) {
      return "alreadyUsed";
    }
    try {
      await this.client.updateEntity(
        { partitionKey: inviteCode, rowKey: INVITE_ROW_KEY, usedBy, usedAt },
        "Merge",
        { etag: entity.etag },
      );
      return "ok";
    } catch (err) {
      if (isPreconditionFailed(err)) {
        return "alreadyUsed";
      }
      throw err;
    }
  }

  /** Idempotent (002 §4.2 step 2 — family deletion's invite revocation, B19). */
  async deleteInvite(inviteCode: string): Promise<void> {
    try {
      await this.client.deleteEntity(inviteCode, INVITE_ROW_KEY);
    } catch (err) {
      if (!isNotFound(err)) throw err;
    }
  }
}
