import { describe, expect, it } from "vitest";
import { buildViewModel, defaultFilters, mergeEdges, transitiveReduction } from "./graph-model";
import type { Graph } from "./types";

const graph: Graph = {
  version: 1,
  project: "T",
  nodes: [
    { id: "App", kind: "app" },
    { id: "Domain", kind: "library", package: "Domain" },
    { id: "DomainMocks", kind: "library", package: "Domain" },
    { id: "Toolkit", kind: "library", package: "Toolkit" },
    { id: "DomainTests", kind: "test", package: "Domain" },
    { id: "Foundation", kind: "system" },
  ],
  edges: [
    { from: "App", to: "Domain", kind: "declared" },
    { from: "App", to: "Domain", kind: "import", count: 3 },
    { from: "App", to: "Toolkit", kind: "declared" },
    { from: "Domain", to: "Toolkit", kind: "import", count: 2 },
    { from: "DomainMocks", to: "Domain", kind: "declared" },
    { from: "DomainTests", to: "Domain", kind: "declared" },
    { from: "Domain", to: "Foundation", kind: "import", count: 9 },
  ],
};

describe("mergeEdges", () => {
  it("merges declared and import edges of one pair", () => {
    const merged = mergeEdges(graph.edges).find((e) => e.from === "App" && e.to === "Domain");
    expect(merged).toEqual({ from: "App", to: "Domain", status: "both", count: 3 });
  });
});

describe("buildViewModel", () => {
  it("hides tests and system modules by default", () => {
    const vm = buildViewModel(graph, defaultFilters);
    expect(vm.nodes.map((n) => n.id)).toEqual(["App", "Domain", "DomainMocks", "Toolkit"]);
    expect(vm.edges.every((e) => e.status === "declared")).toBe(true);
    expect(vm.edges).toHaveLength(3);
  });

  it("shows only the gaps in gaps mode", () => {
    const vm = buildViewModel(graph, { ...defaultFilters, edgeMode: "gaps" });
    expect(vm.edges.map((e) => `${e.from}>${e.to}:${e.status}`).sort()).toEqual([
      "App>Toolkit:declared-only",
      "Domain>Toolkit:import-only",
      "DomainMocks>Domain:declared-only",
    ]);
  });

  it("focuses on a neighbourhood", () => {
    const vm = buildViewModel(graph, { ...defaultFilters, edgeMode: "both", focus: "Toolkit", focusDepth: 1 });
    expect(vm.nodes.map((n) => n.id).sort()).toEqual(["App", "Domain", "Toolkit"]);
  });

  it("groups packages with several targets", () => {
    const vm = buildViewModel(graph, { ...defaultFilters, groupByPackage: true });
    expect([...vm.packages.keys()]).toEqual(["Domain"]);
  });

  it("highlights search matches", () => {
    const vm = buildViewModel(graph, { ...defaultFilters, search: "domain" });
    expect([...vm.highlighted].sort()).toEqual(["Domain", "DomainMocks"]);
  });
});

describe("layers", () => {
  it("computes longest-path depths", () => {
    const vm = buildViewModel(graph, { ...defaultFilters, hideTransitive: false });
    expect([...vm.depths.entries()].sort()).toEqual([["App", 1], ["Domain", 0], ["DomainMocks", 1], ["Toolkit", 0]]);
  });

  it("removes transitive edges and isolated nodes", () => {
    const g: Graph = {
      version: 1, project: "T",
      nodes: [{ id: "A", kind: "app" }, { id: "B", kind: "library" }, { id: "C", kind: "library" }, { id: "Lonely", kind: "library" }],
      edges: [
        { from: "A", to: "B", kind: "declared" }, { from: "B", to: "C", kind: "declared" }, { from: "A", to: "C", kind: "declared" },
      ],
    };
    const vm = buildViewModel(g, defaultFilters);
    expect(vm.edges.map((e) => `${e.from}>${e.to}`)).toEqual(["A>B", "B>C"]);
    expect(vm.transitiveHidden).toBe(1);
    expect(vm.isolated).toEqual(["Lonely"]);
    expect(vm.nodes.map((n) => n.id)).toEqual(["A", "B", "C"]);
  });

  it("keeps a node connected to a cycle it depends on", () => {
    const edges = [{ from: "A", to: "B" }, { from: "A", to: "C" }, { from: "B", to: "C" }, { from: "C", to: "B" }];
    expect(transitiveReduction(edges)).toEqual(edges);
  });

  it("reduces the edges that go around a cycle", () => {
    const edges = [{ from: "A", to: "B" }, { from: "B", to: "C" }, { from: "C", to: "B" }, { from: "C", to: "D" }, { from: "A", to: "D" }];
    expect(transitiveReduction(edges).map((e) => `${e.from}>${e.to}`)).toEqual(["A>B", "B>C", "C>B", "C>D"]);
  });
});
