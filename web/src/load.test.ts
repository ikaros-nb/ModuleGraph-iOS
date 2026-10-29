import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { GraphError, parseGraph } from "./load";

describe("parseGraph", () => {
  it("accepts the CLI output for SampleApp", () => {
    const graph = parseGraph(readFileSync(new URL("../../SampleApp/graph.json", import.meta.url), "utf8"));
    expect(graph.project).toBe("SampleApp");
  });
  it("rejects a dangling edge", () => {
    expect(() => parseGraph(JSON.stringify({ version: 1, project: "x", nodes: [], edges: [{ from: "a", to: "b", kind: "declared" }] }))).toThrow(GraphError);
  });
  it("rejects a wrong version", () => {
    expect(() => parseGraph(JSON.stringify({ version: 2, project: "x", nodes: [], edges: [] }))).toThrow(GraphError);
  });
});
