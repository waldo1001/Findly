import type { FamilyMember, FamilyMeta, FamilyRepo } from "../../src/ports/repositories";

export class InMemoryFamilyRepo implements FamilyRepo {
  private readonly meta = new Map<string, FamilyMeta>();
  private readonly members = new Map<string, Map<string, FamilyMember>>();

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

  /**
   * Test-only seam: deletes ONLY the `meta` row, leaving member rows in place — same idiom
   * as InMemoryGroupRepo.deleteMetaOnlyForTest, used to make exportUserData's defense-in-depth
   * "family meta missing after listMembers succeeded" invariant guard independently testable
   * without a real storage-level partial-failure race.
   */
  deleteMetaOnlyForTest(familyId: string): void {
    this.meta.delete(familyId);
  }
}
