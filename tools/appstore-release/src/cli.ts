import { runCli } from "./main";

// Entry point: `node dist/src/cli.js`. All inputs come from environment variables (see src/config.ts).
runCli({
  env: process.env,
  log: (line) => console.log(line),
  // The step summary is added later (summary writer wiring); until then it is printed.
  writeSummary: (md) => console.log(md),
})
  .then((code) => {
    process.exitCode = code;
  })
  .catch(() => {
    // runCli handles its own errors; this is a last resort that must not print anything sensitive.
    console.error("Unexpected failure.");
    process.exitCode = 1;
  });
