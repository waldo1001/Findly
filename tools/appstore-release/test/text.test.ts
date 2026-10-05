import { describe, expect, it } from "vitest";
import { escapeHtml, maskCommand, oneLine } from "../src/text";

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
    expect(oneLine(`a\r\nb\tc\u0085d e f`)).toBe("a b c d e f");
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
