// specs/001 §1.4 (B29) — the pure server-side normalizer for `displayName` and
// `geofenceName`, applied at every write BEFORE the field's length bound is checked.
// Wired into the zod schemas in src/http/validate.ts (`.transform(normalizeDisplayText)
// .pipe(z.string().min(1).max(N))`) rather than called per use case: a schema-level hook
// applies to every current AND future write path automatically, whereas a per-use-case
// call is one omission away from a silent gap (exactly the shape of bug this task exists
// to close — the length-only check was already applied everywhere, but nothing normalized
// first). Putting the length check in the same `.pipe` also guarantees the bound is always
// evaluated against the NORMALIZED value, never the raw one.
//
// Both fields reach notification surfaces as untrusted text, and on iOS BOTH surfaces are
// SERVER-COMPOSED with no client rendering step at all: `displayName` as the §8.1 locate
// push's title (built by `buildLocateRequestTitle`, corrected 2026-09-07 — the 2026-09-06
// §8.1 amendment made this an alert push with a server-composed `aps.alert.title` on iOS
// too, not only an on-device Android render) and, with `geofenceName`, inside the
// SERVER-COMPOSED §8.2 `GEOFENCE_EVENT` title (built by `titleFor`). Android's on-device
// rendering of the §8.1 `data.requestedByName` leg is covered client-side by A39; the two
// server-composed title builders re-normalize their inputs defensively (B29 residual fix)
// so a value written before this normalizer shipped can't reach either title unclean.
//
// Strip what is NEVER legitimate in a name — Unicode bidirectional embedding/override and
// isolate FORMAT characters (U+202A-U+202E, U+2066-U+2069), every C0 (U+0000-U+001F,
// U+007F) and C1 (U+0080-U+009F) control character, which already covers ASCII newlines
// (U+000A/U+000D) and tabs, plus the Unicode line/paragraph separators (U+2028-U+2029,
// newlines by ECMAScript/Unicode Zl+Zp definition but outside the C0/C1 ranges) — then
// trim ordinary leading/trailing whitespace. Deliberately do NOT touch anything else:
// accents, non-Latin scripts, and emoji are legitimate in real names, and narrowing the
// character set further would exclude real users (spec's explicit instruction — do not
// extend this regex without a corresponding spec change).
//
// Deliberately NOT stripped: U+200E (LEFT-TO-RIGHT MARK), U+200F (RIGHT-TO-LEFT MARK) and
// U+061C (ARABIC LETTER MARK). Unlike the embedding/override/isolate controls above, these
// marks can only nudge the ordering of adjacent neutral characters (punctuation, digits) —
// they cannot reverse or reorder a run of strong-direction text the way U+202E etc. can,
// so they cannot defeat the purpose this stripping serves. Banning them would ban ordinary,
// correct bidi text: right-to-left scripts routinely need one next to a neutral character
// to render correctly, and §1.4 explicitly forbids narrowing the character set to exclude
// real users. Do not add them here without a corresponding spec change.
const FORBIDDEN_CHARS = /[\x00-\x1F\x7F-\x9F\u202A-\u202E\u2066-\u2069\u2028-\u2029]/g;

export function normalizeDisplayText(raw: string): string {
  return raw.replace(FORBIDDEN_CHARS, "").trim();
}
