import "./azuriteEnv";
import { createTableClient } from "../../../src/adapters/tables/tableClientFactory";
import { createContainerClient } from "../../../src/adapters/blobs/blobClientFactory";

/** Azurite doesn't auto-create tables/containers (real Azure provisioning does this once,
 * docs/azure-setup.md); integration tests create-if-not-exists on their own fixtures. */
export async function ensureTables(...names: string[]): Promise<void> {
  for (const name of names) {
    await createTableClient(name).createTable();
  }
}

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
