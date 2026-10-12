import { describe, expect, it } from "vitest";
import { deleteGroup } from "../../../src/domain/group/deleteGroup";
import { InMemoryGroupRepo } from "../../fakes/inMemoryGroupRepo";
import { InMemoryGroupCodeRepo } from "../../fakes/inMemoryGroupCodeRepo";
import { InMemoryGroupExpiryRepo } from "../../fakes/inMemoryGroupExpiryRepo";
import { InMemoryGroupLastKnownRepo } from "../../fakes/inMemoryGroupLastKnownRepo";
import { InMemoryUserRepo } from "../../fakes/inMemoryUserRepo";
import { FixedClock } from "../../fakes/fixedClock";
import { expectAppError } from "../../support/expectAppError";
import type { GroupMeta } from "../../../src/ports/repositories";

const NOW = new Date("2026-07-21T10:00:00Z");

function buildDeps() {
  return {
    groupRepo: new InMemoryGroupRepo(),
    groupCodeRepo: new InMemoryGroupCodeRepo(),
    groupExpiryRepo: new InMemoryGroupExpiryRepo(),
    groupLastKnownRepo: new InMemoryGroupLastKnownRepo(),
    userRepo: new InMemoryUserRepo(),
    clock: new FixedClock(NOW),
  };
}

const ACTIVE_META: GroupMeta = {
  groupId: "grp_a",
  name: "Festival crew",
  ownerUserId: "u1",
  createdAt: "2026-07-20T00:00:00Z",
  endsAt: "2026-08-02T22:00:00Z",
  expiryPolicy: "delete",
  code: "ABCD1234",
};

async function seed(deps: ReturnType<typeof buildDeps>, meta: GroupMeta) {
  await deps.groupRepo.createGroupMeta(meta);
  await deps.groupRepo.addMember(meta.groupId, {
    userId: meta.ownerUserId,
    role: "owner",
    displayName: "Eric",
    joinedAt: meta.createdAt,
  });
  await deps.groupRepo.addMember(meta.groupId, {
    userId: "u9",
    role: "member",
    displayName: "Noor",
    joinedAt: meta.createdAt,
  });
  await deps.groupCodeRepo.createCode(meta.code, { groupId: meta.groupId, createdAt: meta.createdAt });
  if (meta.endsAt !== null) {
    await deps.groupExpiryRepo.putExpiryRow(meta.endsAt.slice(0, 10), meta.groupId, "expire");
  }
  await deps.userRepo.addGroupMembership(meta.ownerUserId, { groupId: meta.groupId, role: "owner", joinedAt: meta.createdAt });
  await deps.userRepo.addGroupMembership("u9", { groupId: meta.groupId, role: "member", joinedAt: meta.createdAt });
}

describe("domain/group/deleteGroup", () => {
  it("throws GROUP_NOT_FOUND for a nonexistent group", async () => {
    const deps = buildDeps();

    await expectAppError(
      deleteGroup({ uid: "u1", familyId: null, groupId: "grp_nope" }, deps),
      "GROUP_NOT_FOUND",
    );
  });

  it("throws GROUP_NOT_FOUND for a caller who is not a member (masked)", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);

    await expectAppError(
      deleteGroup({ uid: "u404", familyId: null, groupId: "grp_a" }, deps),
      "GROUP_NOT_FOUND",
    );
  });

  it("throws AUTH_FORBIDDEN when the caller is a member but not the owner", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);

    await expectAppError(deleteGroup({ uid: "u9", familyId: null, groupId: "grp_a" }, deps), "AUTH_FORBIDDEN");
  });

  it("throws GROUP_NOT_FOUND when meta is gone but an orphaned member row survives (crash mid-sweep)", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);
    deps.groupRepo.deleteMetaOnlyForTest("grp_a");

    await expectAppError(
      deleteGroup({ uid: "u1", familyId: null, groupId: "grp_a" }, deps),
      "GROUP_NOT_FOUND",
    );
  });

  it("hard-deletes a group without an end date (endsAt null, no expiry row exists — 005 §2.5)", async () => {
    const deps = buildDeps();
    await seed(deps, { ...ACTIVE_META, endsAt: null });

    await deleteGroup({ uid: "u1", familyId: null, groupId: "grp_a" }, deps);

    expect(await deps.groupRepo.getGroupMeta("grp_a")).toBeNull();
    expect(await deps.groupRepo.listMembers("grp_a")).toEqual([]);
    expect(await deps.groupCodeRepo.getCode("ABCD1234")).toBeNull();
    expect(await deps.userRepo.listGroupMemberships("u9")).toEqual([]);
  });

  it("hard-deletes meta, all member rows, the code row, both members' reverse-index rows, the expiry row, and the GroupLastKnown partition", async () => {
    const deps = buildDeps();
    await seed(deps, ACTIVE_META);
    deps.groupLastKnownRepo.seed("grp_a", {
      userId: "u1",
      lat: 51.05,
      lon: 3.72,
      accuracyM: 10,
      recordedAt: "2026-07-21T09:00:00Z",
      receivedAt: "2026-07-21T09:00:01Z",
      syncIntervalMinutes: 15,
    });
    deps.groupLastKnownRepo.seed("grp_a", {
      userId: "u9",
      lat: 51.06,
      lon: 3.73,
      accuracyM: 12,
      recordedAt: "2026-07-21T09:00:00Z",
      receivedAt: "2026-07-21T09:00:01Z",
      syncIntervalMinutes: 15,
    });

    await deleteGroup({ uid: "u1", familyId: null, groupId: "grp_a" }, deps);

    expect(await deps.groupRepo.getGroupMeta("grp_a")).toBeNull();
    expect(await deps.groupRepo.listMembers("grp_a")).toEqual([]);
    expect(await deps.groupCodeRepo.getCode("ABCD1234")).toBeNull();
    expect(await deps.userRepo.listGroupMemberships("u1")).toEqual([]);
    expect(await deps.userRepo.listGroupMemberships("u9")).toEqual([]);
    expect(deps.groupExpiryRepo.get("2026-08-02", "grp_a")).toBeUndefined();
    expect(await deps.groupLastKnownRepo.listByGroup("grp_a")).toEqual([]);
  });

  it("succeeds regardless of derived state — archived group", async () => {
    const deps = buildDeps();
    const archiveMeta: GroupMeta = { ...ACTIVE_META, endsAt: "2026-01-01T00:00:00Z", expiryPolicy: "archive" };
    await seed(deps, archiveMeta);

    await deleteGroup({ uid: "u1", familyId: null, groupId: "grp_a" }, deps);

    expect(await deps.groupRepo.getGroupMeta("grp_a")).toBeNull();
  });

  it("succeeds regardless of derived state — expired (not yet swept) delete-policy group", async () => {
    const deps = buildDeps();
    const expiredMeta: GroupMeta = { ...ACTIVE_META, endsAt: "2026-01-02T00:00:00Z", expiryPolicy: "delete" };
    await seed(deps, expiredMeta);

    await deleteGroup({ uid: "u1", familyId: null, groupId: "grp_a" }, deps);

    expect(await deps.groupRepo.getGroupMeta("grp_a")).toBeNull();
  });

  it("succeeds regardless of derived state — ended (grace) group", async () => {
    const deps = buildDeps();
    const graceMeta: GroupMeta = { ...ACTIVE_META, endsAt: "2026-07-20T00:00:00Z", expiryPolicy: "grace" };
    await seed(deps, graceMeta);

    await deleteGroup({ uid: "u1", familyId: null, groupId: "grp_a" }, deps);

    expect(await deps.groupRepo.getGroupMeta("grp_a")).toBeNull();
  });
});
