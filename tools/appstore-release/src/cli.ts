import { runCli } from "./main";
import { makeSummaryWriter } from "./summaryWriter";
import { createMasker } from "./text";

// Entry point: `node dist/cli.js`. All inputs come from environment variables (see src/config.ts).
// DRY_RUN=true makes the HTTP client refuse every non-GET request.
const summaryPath = process.env.GITHUB_STEP_SUMMARY;

runCli({
  env: process.env,
  log: (line) => console.log(line),
  // `::add-mask::` only on GitHub Actions; a local run must never print the key or a token.
  mask: createMasker(process.env, (line) => console.log(line)),
  writeSummary: makeSummaryWriter(summaryPath && summaryPath !== "" ? summaryPath : undefined),
})
  .then((code) => {
    process.exitCode = code;
  })
  .catch(() => {
    // runCli handles its own errors; this is a last resort that must not print anything sensitive.
    console.error("Unexpected failure.");
    process.exitCode = 1;
  });
