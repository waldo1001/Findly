import { generateKeyPairSync } from "node:crypto";
import { describe, expect, it } from "vitest";
import { MAX_NOTES_LENGTH, loadConfig, parseDryRun, parseNotes } from "../src/config";

describe("parseNotes (RELEASE_NOTES)", () => {
  it("trims surrounding whitespace and keeps inner line breaks", () => {
    expect(parseNotes("  Bug fixes.\n\nMore fixes.  \n")).toBe("Bug fixes.\n\nMore fixes.");
  });

  it("rejects missing, empty and whitespace-only notes", () => {
    for (const bad of [undefined, "", "   ", "\n\t "]) {
      expect(() => parseNotes(bad)).toThrow(/RELEASE_NOTES/);
    }
  });

  it("accepts exactly 4000 characters and rejects 4001", () => {
    expect(MAX_NOTES_LENGTH).toBe(4000);
    expect(parseNotes("x".repeat(4000))).toHaveLength(4000);
    expect(() => parseNotes("x".repeat(4001))).toThrow(/4000/);
  });

  it("measures the length after trimming", () => {
    expect(parseNotes(`  ${"x".repeat(4000)}  `)).toHaveLength(4000);
  });
});

describe("parseDryRun (DRY_RUN) fails closed", () => {
  it("accepts true/false in any case with whitespace", () => {
    expect(parseDryRun("true")).toBe(true);
    expect(parseDryRun(" TRUE ")).toBe(true);
    expect(parseDryRun("false")).toBe(false);
    expect(parseDryRun("False")).toBe(false);
  });

  it("refuses anything else, so a typo or an unset variable can never start a live release", () => {
    for (const bad of [undefined, "", "yes", "no", "1", "0", "ture", "dry"]) {
      expect(() => parseDryRun(bad)).toThrow(/DRY_RUN/);
    }
  });
});

describe("loadConfig", () => {
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const pem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
  const base = {
    ASC_KEY_ID: "WV483G2U79",
    ASC_ISSUER_ID: "11111111-2222-3333-4444-555555555555",
    ASC_API_KEY_P8: Buffer.from(pem).toString("base64"),
    RELEASE_NOTES: " Fresh notes ",
    DRY_RUN: "true",
  };

  it("builds the config, decoding the base64 key into a PEM and trimming the notes", () => {
    const cfg = loadConfig({ ...base, GITHUB_STEP_SUMMARY: "/tmp/summary.md" });
    expect(cfg.keyId).toBe("WV483G2U79");
    expect(cfg.issuerId).toBe(base.ASC_ISSUER_ID);
    expect(cfg.privateKey).toBe(pem);
    expect(cfg.notes).toBe("Fresh notes");
    expect(cfg.dryRun).toBe(true);
    expect(cfg.appId).toBe("6797994768");
    expect(cfg.summaryPath).toBe("/tmp/summary.md");
  });

  it("names every missing variable, never any value", () => {
    let message = "";
    try {
      loadConfig({ ASC_API_KEY_P8: base.ASC_API_KEY_P8, RELEASE_NOTES: "n", DRY_RUN: "false" });
    } catch (e) {
      message = (e as Error).message;
    }
    expect(message).toContain("ASC_KEY_ID");
    expect(message).toContain("ASC_ISSUER_ID");
    expect(message).not.toContain(base.ASC_API_KEY_P8);
  });

  it("surfaces a bad key without echoing it", () => {
    let message = "";
    try {
      loadConfig({ ...base, ASC_API_KEY_P8: "garbage-SENTINEL" });
    } catch (e) {
      message = (e as Error).message;
    }
    expect(message).toMatch(/ASC_API_KEY_P8/);
    expect(message).not.toContain("SENTINEL");
  });

  it("propagates a DRY_RUN or notes problem", () => {
    expect(() => loadConfig({ ...base, DRY_RUN: "maybe" })).toThrow(/DRY_RUN/);
    expect(() => loadConfig({ ...base, RELEASE_NOTES: " " })).toThrow(/RELEASE_NOTES/);
  });
});
