import { describe, expect, it } from "vitest";
import { createMasker, escapeHtml, maskCommand, oneLine } from "../src/text";

describe("oneLine (log text must never start a workflow command)", () => {
  it("defuses a line that would start with ::", () => {
    const out = oneLine("::error::boom");
    expect(out.startsWith("::")).toBe(false);
    expect(out).toContain("error::boom");
  });

  it("defuses :: even after control characters and whitespace are stripped", () => {
    expect(oneLine("\n\r  ::add-mask::x").startsWith("::")).toBe(false);
  });

  it("leaves :: in the middle of a line alone", () => {
    expect(oneLine("Foo::bar")).toBe("Foo::bar");
  });

  it("collapses CR, LF, tabs, NEL and the Unicode line/paragraph separators to single spaces", () => {
    const ls = String.fromCharCode(0x2028);
    const ps = String.fromCharCode(0x2029);
    expect(oneLine(`a\r\nb\tc\u0085d${ls}e${ps}f`)).toBe("a b c d e f");
  });

  it("trims the ends", () => {
    expect(oneLine("  hello \n")).toBe("hello");
  });
});

describe("maskCommand", () => {
  it("renders the add-mask workflow command for a single-line value", () => {
    expect(maskCommand("abc.def.ghi")).toBe("::add-mask::abc.def.ghi");
  });

  it("refuses multi-line values (each line must be masked on its own) and empty ones", () => {
    expect(() => maskCommand("a\nb")).toThrow();
    expect(() => maskCommand("a\rb")).toThrow();
    expect(() => maskCommand("")).toThrow();
  });
});

describe("escapeHtml", () => {
  it("escapes &, < and >", () => {
    expect(escapeHtml("a & <b>")).toBe("a &amp; &lt;b&gt;");
  });
});

describe("createMasker (credentials must not be printed outside GitHub Actions)", () => {
  it("on GitHub Actions (GITHUB_ACTIONS=true) prints the add-mask command", () => {
    const printed: string[] = [];
    createMasker({ GITHUB_ACTIONS: "true" }, (l) => printed.push(l))("abc.def");
    expect(printed).toEqual(["::add-mask::abc.def"]);
  });

  it.each([undefined, "", "false", "TRUE", "1", "yes"])("prints nothing when GITHUB_ACTIONS=%j (a local run must not echo the key or tokens)", (value) => {
    const printed: string[] = [];
    const mask = createMasker({ GITHUB_ACTIONS: value }, (l) => printed.push(l));
    mask("-----BEGIN-body-line");
    mask("eyJhbGciOiJFUzI1NiJ9.payload.signature");
    expect(printed).toEqual([]);
  });

  it("does not look at anything but GITHUB_ACTIONS", () => {
    const printed: string[] = [];
    createMasker({ CI: "true", GITHUB_STEP_SUMMARY: "/tmp/x" }, (l) => printed.push(l))("secret");
    expect(printed).toEqual([]);
  });
});
