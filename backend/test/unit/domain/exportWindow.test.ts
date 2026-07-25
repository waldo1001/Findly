import { describe, expect, it } from "vitest";
import { resolveExportWindow } from "../../../src/domain/export/exportWindow";

// specs/002 §4 (physical retention: "delete at 400 d") / specs/008 §3 — export reads the
// FULL physical retention window, deliberately beyond features.limits.historyDays. Pure,
// mutation-tested directly (kills off-by-one / literal-flip mutants on the 400-day constant).
describe("domain/export/exportWindow", () => {
  it("returns [now-400d, now] as UTC calendar dates", () => {
    const now = new Date("2026-07-25T14:00:00Z");

    expect(resolveExportWindow(now)).toEqual({ from: "2025-06-20", to: "2026-07-25" });
  });

  it("`to` is always today's UTC date regardless of time-of-day", () => {
    expect(resolveExportWindow(new Date("2026-07-25T00:00:00.001Z")).to).toBe("2026-07-25");
    expect(resolveExportWindow(new Date("2026-07-25T23:59:59.999Z")).to).toBe("2026-07-25");
  });

  it("the span is exactly 400 days (not 399 or 401)", () => {
    const { from, to } = resolveExportWindow(new Date("2026-07-25T12:00:00Z"));
    const spanDays = (Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / (24 * 60 * 60 * 1000);
    expect(spanDays).toBe(400);
  });

  it("crosses a year boundary correctly", () => {
    const now = new Date("2026-01-10T09:00:00Z");

    expect(resolveExportWindow(now)).toEqual({ from: "2024-12-06", to: "2026-01-10" });
  });
});
