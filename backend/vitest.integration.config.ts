import { defineConfig } from "vitest/config";

// Storage-adapter integration tests (specs/002 §6). Requires Azurite running locally
// (`npm run dev:storage`) or in CI; deliberately a separate vitest project from the
// default config so `npm test` (unit only) never touches Azurite or the network. Run with
// `npm run test:integration`.
export default defineConfig({
  test: {
    include: ["test/integration/**/*.test.ts"],
    environment: "node",
    testTimeout: 30_000,
    hookTimeout: 30_000,
    // B20 (specs/002 §4.2, 008 §9): the "never-created table/container" tests delete a
    // table/container that OTHER files' beforeAll hooks also depend on existing (Azurite
    // state is a shared external process, not reset per file). Running files in parallel
    // would let one file's delete race another file's concurrent use of the same shared
    // table name. Serializing keeps every file's own beforeAll (idempotent create) and
    // teardown deterministic; this suite is small enough that the cost is negligible.
    fileParallelism: false,
  },
});
