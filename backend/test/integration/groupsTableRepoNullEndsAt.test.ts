// specs/002 §2.10, specs/005 §2.5 — B39: `Groups.meta.endsAt` is nullable ("no end date").
// Table Storage has no null type: the @azure/data-tables SDK silently DROPS null-valued
// properties from a Merge payload (the B21 trap, see usersTableRepoClearFamilyMembership), so
// `updateEntity({ endsAt: null }, "Merge")` would succeed while leaving the old date in place —
// a group the owner just made endless would still expire. Write omits the property for null,
// read maps absent -> null, and clearing an existing value needs a guarded Replace. These tests
// read the RAW entity as well, never only the port. Requires Azurite (`npm run dev:storage`);
// run via `npm run test:integration`.

import { randomUUID } from "node:crypto";
import { beforeAll, describe, expect, it } from "vitest";
import { ensureTables } from "./support/ensureStorage";
import { testGroupId, testUserId } from "./support/ids";
import { createTableClient } from "../../src/adapters/tables/tableClientFactory";
import { TableGroupRepo } from "../../src/adapters/tables/groupsTableRepo";
import type { GroupMeta } from "../../src/ports/repositories";

const META_ROW_KEY = "meta";

function newMeta(overrides: Partial<GroupMeta> = {}): GroupMeta {
  return {
    groupId: testGroupId(),
    name: "Integration crew",
    ownerUserId: testUserId(),
    createdAt: "2026-07-01T00:00:00Z",
    endsAt: "2026-08-02T22:00:00Z",
    expiryPolicy: "grace",
    code: randomUUID().replace(/-/g, "").slice(0, 8).toUpperCase(),
    ...overrides,
  };
}

async function rawMeta(groupId: string) {
  return createTableClient("Groups").getEntity(groupId, META_ROW_KEY);
}

describe("integration/Groups.meta endsAt null round-trip (specs/002 §2.10, 005 §2.5, B39)", () => {
  beforeAll(async () => {
    await ensureTables("Groups");
  }, 30_000);

  it("createGroupMeta with endsAt null OMITS the property and getGroupMeta reads absent back as null", async () => {
    const repo = new TableGroupRepo();
    const meta = newMeta({ endsAt: null });

    await repo.createGroupMeta(meta);

    const raw = await rawMeta(meta.groupId);
    expect(raw.endsAt).toBeUndefined();
    expect(raw.name).toBe("Integration crew");
    const read = await repo.getGroupMeta(meta.groupId);
    expect(read).toMatchObject({ groupId: meta.groupId, endsAt: null, expiryPolicy: "grace", code: meta.code });
  });

  it("a dated endsAt still round-trips as the ISO string", async () => {
    const repo = new TableGroupRepo();
    const meta = newMeta();

    await repo.createGroupMeta(meta);

    expect((await repo.getGroupMeta(meta.groupId))?.endsAt).toBe("2026-08-02T22:00:00Z");
  });

  it("updateGroupMeta({ endsAt: null }) REALLY clears a stored date (raw entity has no endsAt) and keeps every other column", async () => {
    const repo = new TableGroupRepo();
    const meta = newMeta();
    await repo.createGroupMeta(meta);

    const updated = await repo.updateGroupMeta(meta.groupId, { endsAt: null });

    expect(updated.endsAt).toBeNull();
    const raw = await rawMeta(meta.groupId);
    expect(raw.endsAt).toBeUndefined();
    expect(raw.name).toBe("Integration crew");
    expect(raw.ownerUserId).toBe(meta.ownerUserId);
    expect(raw.createdAt).toBe(meta.createdAt);
    expect(raw.expiryPolicy).toBe("grace");
    expect(raw.code).toBe(meta.code);
    expect((await repo.getGroupMeta(meta.groupId))?.endsAt).toBeNull();
  });

  it("updateGroupMeta({ endsAt: null, name }) clears the date and applies the rename in the same write", async () => {
    const repo = new TableGroupRepo();
    const meta = newMeta();
    await repo.createGroupMeta(meta);

    const updated = await repo.updateGroupMeta(meta.groupId, { endsAt: null, name: "Renamed" });

    expect(updated).toMatchObject({ endsAt: null, name: "Renamed", code: meta.code });
    expect((await rawMeta(meta.groupId)).name).toBe("Renamed");
  });

  it("updateGroupMeta({ endsAt: <instant> }) sets a date on a no-end group (null -> instant)", async () => {
    const repo = new TableGroupRepo();
    const meta = newMeta({ endsAt: null });
    await repo.createGroupMeta(meta);

    const updated = await repo.updateGroupMeta(meta.groupId, { endsAt: "2026-09-09T09:00:00Z" });

    expect(updated.endsAt).toBe("2026-09-09T09:00:00Z");
    expect((await repo.getGroupMeta(meta.groupId))?.endsAt).toBe("2026-09-09T09:00:00Z");
  });

  it("a rename (no endsAt key) leaves a null endsAt null, and a code rotation too", async () => {
    const repo = new TableGroupRepo();
    const meta = newMeta({ endsAt: null });
    await repo.createGroupMeta(meta);

    await repo.updateGroupMeta(meta.groupId, { name: "Only a rename" });
    const afterRotate = await repo.updateGroupMeta(meta.groupId, { code: "NEWCODE9" });

    expect(afterRotate).toMatchObject({ endsAt: null, name: "Only a rename", code: "NEWCODE9" });
  });

  it("updateGroupMeta({ endsAt: null }) on an already-null group is idempotent", async () => {
    const repo = new TableGroupRepo();
    const meta = newMeta({ endsAt: null });
    await repo.createGroupMeta(meta);

    const updated = await repo.updateGroupMeta(meta.groupId, { endsAt: null });

    expect(updated.endsAt).toBeNull();
  });
});
