// specs/001 §1.4 (B29) — normalizeDisplayText is the pure server-side normalizer applied
// to `displayName` and `geofenceName` at every write, BEFORE the field's length bound is
// checked. Exhaustive unit coverage lives here (mutation-tested); src/http/validate.ts
// wires it into the zod schemas and is covered separately (test/unit/http/validate.test.ts).

import { describe, expect, it } from "vitest";
import { normalizeDisplayText } from "../../../src/domain/text/normalizeDisplayText";

describe("domain/text/normalizeDisplayText", () => {
  it("leaves an ordinary name untouched", () => {
    expect(normalizeDisplayText("Eric")).toBe("Eric");
  });

  it("passes accented characters through untouched", () => {
    expect(normalizeDisplayText("José Núñez")).toBe("José Núñez");
  });

  it("passes non-Latin scripts through untouched", () => {
    expect(normalizeDisplayText("田中太郎")).toBe("田中太郎");
  });

  it("passes emoji through untouched", () => {
    expect(normalizeDisplayText("Eric 🚀👍")).toBe("Eric 🚀👍");
  });

  it("trims ordinary leading/trailing spaces", () => {
    expect(normalizeDisplayText("  Eric  ")).toBe("Eric");
  });

  it("strips a right-to-left override (U+202E) embedded mid-string", () => {
    expect(normalizeDisplayText("Eric\u202Esirhc")).toBe("Ericsirhc");
  });

  it("strips each bidi embedding/override control (U+202A-U+202E)", () => {
    for (let code = 0x202a; code <= 0x202e; code++) {
      const ch = String.fromCharCode(code);
      expect(normalizeDisplayText(`A${ch}B`)).toBe("AB");
    }
  });

  it("strips each bidi isolate control (U+2066-U+2069)", () => {
    for (let code = 0x2066; code <= 0x2069; code++) {
      const ch = String.fromCharCode(code);
      expect(normalizeDisplayText(`A${ch}B`)).toBe("AB");
    }
  });

  it("strips an embedded newline (LF)", () => {
    expect(normalizeDisplayText("Eric\nSmith")).toBe("EricSmith");
  });

  it("strips an embedded carriage return", () => {
    expect(normalizeDisplayText("Eric\rSmith")).toBe("EricSmith");
  });

  it("strips a C0 control character (e.g. U+0007 BEL)", () => {
    expect(normalizeDisplayText("Eric\u0007Smith")).toBe("EricSmith");
  });

  it("strips DEL (U+007F)", () => {
    expect(normalizeDisplayText("Eric\u007FSmith")).toBe("EricSmith");
  });

  it("strips a C1 control character (e.g. U+0085 NEL)", () => {
    expect(normalizeDisplayText("Eric\u0085Smith")).toBe("EricSmith");
  });

  it("strips every C0 control character (U+0000-U+001F)", () => {
    for (let code = 0x00; code <= 0x1f; code++) {
      const ch = String.fromCharCode(code);
      expect(normalizeDisplayText(`A${ch}B`)).toBe("AB");
    }
  });

  it("strips every C1 control character (U+0080-U+009F)", () => {
    for (let code = 0x80; code <= 0x9f; code++) {
      const ch = String.fromCharCode(code);
      expect(normalizeDisplayText(`A${ch}B`)).toBe("AB");
    }
  });

  it("a name that is only control/bidi characters normalizes to the empty string", () => {
    expect(normalizeDisplayText("\u202E\u0007\n\u2066")).toBe("");
  });

  it("normalizes a control-only name to empty rather than a whitespace-padded stand-in", () => {
    const result = normalizeDisplayText("\u202E\u202E");
    expect(result).toBe("");
    expect(result).toHaveLength(0);
  });

  it("strips control characters everywhere in the string, not only at the edges", () => {
    expect(normalizeDisplayText("A\u0001B\u0002C")).toBe("ABC");
  });

  it("strips characters first, then trims — a name that is spaces around a stripped control collapses fully", () => {
    expect(normalizeDisplayText("  \u202E  ")).toBe("");
  });

  it("does not collapse or alter internal ordinary whitespace", () => {
    expect(normalizeDisplayText("Eric van der Berg")).toBe("Eric van der Berg");
  });

  it("is idempotent: normalizing an already-normalized value is a no-op", () => {
    const once = normalizeDisplayText("Eric\u202E van\u0007 Berg  ");
    expect(normalizeDisplayText(once)).toBe(once);
  });
});
