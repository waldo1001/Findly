// C0 controls, DEL, NEL and the Unicode line/paragraph separators, as an escaped string so no raw
// separator character ever appears in this source file.
const LINE_BREAKERS = new RegExp("[\\u0000-\\u001f\\u007f\\u0085\\u2028\\u2029]+", "g");

/**
 * Log text can echo store-supplied strings (Apple error details, version strings) and operator input
 * (release notes). GitHub Actions interprets `::command::` at the start of a log line, so everything
 * logged is forced onto one line first, and a leading `::` is defused.
 */
export function oneLine(text: string): string {
  return text.replace(LINE_BREAKERS, " ").trim().replace(/^::/, ": :");
}

const LINE_SPLIT = new RegExp("\\r\\n|[\\r\\n\\u2028\\u2029]");

/** Splits on every kind of line break `oneLine` treats as one (again escaped, never raw, in this source). */
export function splitLines(text: string): string[] {
  return text.split(LINE_SPLIT);
}

/**
 * GitHub's `::add-mask::` workflow command for a single-line value. Emitted directly (never through
 * {@link oneLine}, which would defuse it). A multi-line value must be masked line by line.
 */
export function maskCommand(value: string): string {
  if (value === "" || /[\r\n]/.test(value)) throw new Error("maskCommand needs a non-empty single-line value.");
  return `::add-mask::${value}`;
}

/**
 * The mask hook for the CLI. `::add-mask::` is only meaningful to the GitHub Actions runner, which consumes
 * the command line. Anywhere else (a local `npm start`) nothing would consume it and the credential, the
 * decoded `.p8` lines and every JWT, would be printed in clear text, so outside Actions it does nothing.
 */
export function createMasker(env: Record<string, string | undefined>, print: (line: string) => void): (value: string) => void {
  if (env.GITHUB_ACTIONS !== "true") return () => undefined;
  return (value) => print(maskCommand(value));
}

export function escapeHtml(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
