import { describe, expect, it } from "vitest";
import schema from "../../schema/graph.schema.json";
import { kindColors } from "./theme";
import type { EdgeKind } from "./types";

// types.ts restates the schema by hand: catch the two drifting apart. A Record must name every kind, and only those.
describe("graph.schema.json", () => {
  it("has the node kinds of types.ts", () => {
    expect(schema.properties.nodes.items.properties.kind.enum).toEqual(Object.keys(kindColors));
  });
  it("has the edge kinds of types.ts", () => {
    const edgeKinds: Record<EdgeKind, true> = { declared: true, import: true };
    expect(schema.properties.edges.items.properties.kind.enum).toEqual(Object.keys(edgeKinds));
  });
});
