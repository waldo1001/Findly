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

export function escapeHtml(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
