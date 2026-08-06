import "./azuriteEnv";
import { createTableClient } from "../../../src/adapters/tables/tableClientFactory";
import { createContainerClient } from "../../../src/adapters/blobs/blobClientFactory";

/** Azurite doesn't auto-create tables (real Azure provisioning does this once,
 * docs/azure-setup.md; specs/002 §1, B23); integration tests create-if-not-exists on their
 * own fixtures. NOTE this is NOT true of blob containers — see `ensureContainers` below. */
export async function ensureTables(...names: string[]): Promise<void> {
  for (const name of names) {
    await createTableClient(name).createTable();
  }
}

/** Unlike `ensureTables`, this is not fighting Azurite's own behavior — Azurite auto-creates
 * containers implicitly on write. It exists so every test file's `beforeAll` can idempotently
 * restore whatever a sibling test's `dropContainers` (below) deliberately removed, deterministically,
 * without depending on a subsequent write happening to recreate it first (specs/002 §1, B25). */
export async function ensureContainers(...names: string[]): Promise<void> {
  for (const name of names) {
    await createContainerClient(name).createIfNotExists();
  }
}

/** B20 (specs/002 §4.2, 008 §9) — drops a table entirely (not just its rows), so a test can
 * prove erasure/read adapters tolerate a table that has never been created (TableNotFound),
 * the class of storage state the account-reset step in docs/azure-setup.md produces and the
 * one no other integration test in this suite exercises. `deleteTable()` itself already
 * tolerates the table not existing, so this is safe to call unconditionally. Callers MUST run
 * with `fileParallelism: false` (vitest.integration.config.ts) since this deletes tables other
 * test FILES' `beforeAll` hooks also depend on existing. */
export async function dropTables(...names: string[]): Promise<void> {
  for (const name of names) {
    await createTableClient(name).deleteTable();
  }
}

/** Same idea as dropTables, for containers (ContainerNotFound). `deleteIfExists()` already
 * tolerates the container not existing. */
export async function dropContainers(...names: string[]): Promise<void> {
  for (const name of names) {
    await createContainerClient(name).deleteIfExists();
  }
}
