import { describe, it, expect } from "vitest";
import { computeNewItems, isFirstRun } from "./diff";
import type { Item } from "./diff";

function make(id: string): Item {
  return { id, title: id, link: `http://x/${id}`, pubDate: "2024-01-01" };
}

describe("diff", () => {
  it("returns new items not in known set", () => {
    const items = [make("A"), make("B"), make("C")];
    expect(computeNewItems(items, new Set(["A"])).map((i) => i.id)).toEqual(["B", "C"]);
  });
  it("returns empty when no new", () => {
    const items = [make("A"), make("B")];
    expect(computeNewItems(items, new Set(["A", "B", "C"]))).toEqual([]);
  });
  it("baseline: all new on empty known", () => {
    expect(isFirstRun(new Set())).toBe(true);
    const items = [make("A"), make("B")];
    expect(computeNewItems(items, new Set())).toHaveLength(2);
  });
  it("non-empty known is not first run", () => {
    expect(isFirstRun(new Set(["A"]))).toBe(false);
  });
  it("duplicate ids in feed handled", () => {
    const items = [make("A"), make("A")];
    expect(computeNewItems(items, new Set())).toHaveLength(2);
  });
});
