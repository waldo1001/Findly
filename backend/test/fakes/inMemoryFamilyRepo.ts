import type { FamilyInviteIndexEntry, FamilyMember, FamilyMeta, FamilyRepo } from "../../src/ports/repositories";

export class InMemoryFamilyRepo implements FamilyRepo {
  private readonly meta = new Map<string, FamilyMeta>();
  private readonly members = new Map<string, Map<string, FamilyMember>>();
  private readonly inviteIndex = new Map<string, Map<string, FamilyInviteIndexEntry>>();

  /** Synchronous test-setup helper (mirrors InMemoryEntitlementsRepo.seed) — bypasses the
   * conditional-insert semantics of createFamily so callers can seed synchronously inside a
   * non-async buildDeps(). */
  seed(meta: FamilyMeta): void {
    this.meta.set(meta.familyId, { ...meta });
    if (!this.members.has(meta.familyId)) {
      this.members.set(meta.familyId, new Map());
    }
  }

  async createFamily(meta: FamilyMeta): Promise<void> {
    if (this.meta.has(meta.familyId)) {
      throw new Error(`InMemoryFamilyRepo: family ${meta.familyId} already exists`);
    }
    this.meta.set(meta.familyId, { ...meta });
    this.members.set(meta.familyId, new Map());
  }

  async getFamilyMeta(familyId: string): Promise<FamilyMeta | null> {
    const meta = this.meta.get(familyId);
    return meta ? { ...meta } : null;
  }

  async addMember(familyId: string, member: FamilyMember): Promise<void> {
    const roster = this.members.get(familyId);
    if (!roster) {
      throw new Error(`InMemoryFamilyRepo: no family ${familyId}`);
    }
    roster.set(member.userId, { ...member });
  }

  async listMembers(familyId: string): Promise<FamilyMember[]> {
    const roster = this.members.get(familyId);
    return roster ? [...roster.values()].map((m) => ({ ...m })) : [];
  }

  async updateMember(
    familyId: string,
    userId: string,
    patch: Partial<Pick<FamilyMember, "role" | "displayName">>,
  ): Promise<FamilyMember> {
    const roster = this.members.get(familyId);
    const existing = roster?.get(userId);
    if (!roster || !existing) {
      throw new Error(`InMemoryFamilyRepo: no member ${userId} in family ${familyId}`);
    }
    const updated = { ...existing, ...patch };
    roster.set(userId, updated);
    return { ...updated };
  }

  async removeMember(familyId: string, userId: string): Promise<void> {
    this.members.get(familyId)?.delete(userId);
  }

  async addInviteIndexEntry(familyId: string, entry: FamilyInviteIndexEntry): Promise<void> {
    const index = this.inviteIndex.get(familyId) ?? new Map();
    index.set(entry.code, { ...entry });
    this.inviteIndex.set(familyId, index);
  }

  async listInviteIndexEntries(familyId: string): Promise<FamilyInviteIndexEntry[]> {
    const index = this.inviteIndex.get(familyId);
    return index ? [...index.values()].map((e) => ({ ...e })) : [];
  }

  async removeInviteIndexEntry(familyId: string, code: string): Promise<void> {
    this.inviteIndex.get(familyId)?.delete(code);
  }

  async deleteFamilyMeta(familyId: string): Promise<void> {
    this.meta.delete(familyId);
  }
}
