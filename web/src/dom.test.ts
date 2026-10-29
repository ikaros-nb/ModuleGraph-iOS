import { afterAll, describe, expect, it, vi } from "vitest";
import { h } from "./dom";

// Vitest has no DOM here: a stand-in document records what h() builds, and fails on any use of innerHTML.
class FakeElement {
  attributes = new Map<string, string>();
  children: unknown[] = [];
  readonly tag: string;
  constructor(tag: string) {
    this.tag = tag;
  }
  setAttribute(name: string, value: string) {
    this.attributes.set(name, value);
  }
  append(...children: unknown[]) {
    this.children.push(...children);
  }
  set innerHTML(_: string) {
    throw new Error("innerHTML used");
  }
}
vi.stubGlobal("document", { createElement: (tag: string) => new FakeElement(tag), createTextNode: (data: string) => ({ data }) });
afterAll(() => void vi.unstubAllGlobals());

describe("h", () => {
  const payload = `<img src=x onerror="alert('x')">`;

  it("adds strings as text, never as markup", () => {
    const li = h("li", {}, payload, 3) as unknown as FakeElement;
    expect(li.children).toEqual([{ data: payload }, { data: "3" }]);
  });
  it("sets attributes verbatim, without building markup", () => {
    const button = h("button", { "data-id": payload }) as unknown as FakeElement;
    expect(button.attributes.get("data-id")).toBe(payload);
  });
  it("nests elements and skips empty children", () => {
    const code = h("code", {}, "x");
    const dd = h("dd", {}, code, null, false, undefined) as unknown as FakeElement;
    expect(dd.children).toEqual([code]);
  });
});
