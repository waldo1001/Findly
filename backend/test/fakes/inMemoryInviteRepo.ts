import type { ConsumeInviteResult, InviteRecord, InviteRepo } from "../../src/ports/repositories";

export class InMemoryInviteRepo implements InviteRepo {
  private readonly invites = new Map<string, InviteRecord>();

  async createInvite(invite: InviteRecord): Promise<void> {
    this.invites.set(invite.inviteCode, { ...invite });
  }

  async getInvite(inviteCode: string): Promise<InviteRecord | null> {
    const invite = this.invites.get(inviteCode);
    return invite ? { ...invite } : null;
  }

  /**
   * ETag-guarded-merge semantics (002 §2.3), simulated in-memory: the check-and-set below
   * has no `await` inside it, so it runs to completion synchronously once called — exactly
   * one of two racing calls observes `usedBy` unset and wins; the other sees it already set.
   */
  async consumeInvite(inviteCode: string, usedBy: string, usedAt: string): Promise<ConsumeInviteResult> {
    const invite = this.invites.get(inviteCode);
    if (!invite) {
      throw new Error(`InMemoryInviteRepo: no invite ${inviteCode}`);
    }
    if (invite.usedBy) {
      return "alreadyUsed";
    }
    this.invites.set(inviteCode, { ...invite, usedBy, usedAt });
    return "ok";
  }

  async deleteInvite(inviteCode: string): Promise<void> {
    this.invites.delete(inviteCode);
  }
}
