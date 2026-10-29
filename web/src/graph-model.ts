import type { Graph, GraphEdge, GraphNode } from "./types";

export type EdgeMode = "declared" | "import" | "both" | "gaps";
export type LayoutMode = "onion" | "layers" | "force";

export interface Filters {
  showTests: boolean;
  showSystem: boolean;
  showExternal: boolean;
  edgeMode: EdgeMode;
  groupByPackage: boolean;
  search: string;
  focus: string | null;
  focusDepth: number;
  layout: LayoutMode;
  hideTransitive: boolean;
  hideIsolated: boolean;
}

export const defaultFilters: Filters = {
  showTests: false,
  showSystem: false,
  showExternal: false,
  edgeMode: "declared",
  groupByPackage: false,
  search: "",
  focus: null,
  focusDepth: 1,
  layout: "onion",
  hideTransitive: true,
  hideIsolated: true,
};

export interface ViewEdge {
  from: string;
  to: string;
  /** declared, import, both, declared-only (gap) or import-only (gap) */
  status: "declared" | "import" | "both" | "declared-only" | "import-only";
  count: number;
}

export interface ViewModel {
  nodes: GraphNode[];
  edges: ViewEdge[];
  /** package name -> node ids, when groupByPackage is on */
  packages: Map<string, string[]>;
  highlighted: Set<string>;
  /** longest-path depth of each visible node, 0 for the leaves */
  depths: Map<string, number>;
  /** nodes removed because nothing visible connects to them */
  isolated: string[];
  /** edges removed by the transitive reduction */
  transitiveHidden: number;
}

const pairKey = (e: { from: string; to: string }) => `${e.from}\u0000${e.to}`;

/** Merge declared and import edges of the same pair into one ViewEdge. */
export function mergeEdges(edges: GraphEdge[]): ViewEdge[] {
  const byPair = new Map<string, { from: string; to: string; declared: boolean; count: number }>();
  for (const e of edges) {
    const key = pairKey(e);
    const entry = byPair.get(key) ?? { from: e.from, to: e.to, declared: false, count: 0 };
    if (e.kind === "declared") entry.declared = true;
    else entry.count += e.count ?? 1;
    byPair.set(key, entry);
  }
  return [...byPair.values()].map((e) => ({
    from: e.from,
    to: e.to,
    count: e.count,
    status: e.declared && e.count > 0 ? "both" : e.declared ? "declared-only" : "import-only",
  }));
}

function neighbourhood(ids: Set<string>, edges: ViewEdge[], start: string, depth: number): Set<string> {
  const seen = new Set<string>([start]);
  let frontier = [start];
  for (let d = 0; d < depth && frontier.length; d++) {
    const next: string[] = [];
    for (const e of edges) {
      for (const [a, b] of [[e.from, e.to], [e.to, e.from]]) {
        if (frontier.includes(a) && ids.has(b) && !seen.has(b)) {
          seen.add(b);
          next.push(b);
        }
      }
    }
    frontier = next;
  }
  return seen;
}

export function buildViewModel(graph: Graph, filters: Filters): ViewModel {
  const hasImportEdges = graph.edges.some((e) => e.kind === "import");
  let nodes = graph.nodes.filter(
    (n) => (filters.showTests || n.kind !== "test") && (filters.showSystem || n.kind !== "system") && (filters.showExternal || n.kind !== "external"),
  );
  let ids = new Set(nodes.map((n) => n.id));
  let merged = mergeEdges(graph.edges.filter((e) => ids.has(e.from) && ids.has(e.to)));

  let edges: ViewEdge[];
  switch (filters.edgeMode) {
    case "declared":
      edges = merged.filter((e) => e.status !== "import-only").map((e) => ({ ...e, status: "declared" as const }));
      break;
    case "import":
      edges = merged.filter((e) => e.status !== "declared-only").map((e) => ({ ...e, status: "import" as const }));
      break;
    case "gaps":
      edges = hasImportEdges ? merged.filter((e) => e.status !== "both") : [];
      break;
    default:
      edges = merged;
  }

  if (filters.focus && ids.has(filters.focus)) {
    const keep = neighbourhood(ids, edges, filters.focus, filters.focusDepth);
    nodes = nodes.filter((n) => keep.has(n.id));
    ids = new Set(nodes.map((n) => n.id));
    edges = edges.filter((e) => ids.has(e.from) && ids.has(e.to));
  }

  let transitiveHidden = 0;
  if (filters.hideTransitive && filters.edgeMode !== "gaps") {
    const reduced = transitiveReduction(edges);
    transitiveHidden = edges.length - reduced.length;
    edges = reduced;
  }

  let isolated: string[] = [];
  if (filters.hideIsolated && !filters.focus) {
    const connected = new Set(edges.flatMap((e) => [e.from, e.to]));
    isolated = nodes.filter((n) => !connected.has(n.id)).map((n) => n.id);
    if (isolated.length < nodes.length) nodes = nodes.filter((n) => connected.has(n.id));
    else isolated = [];
  }

  const depths = layerDepths(nodes.map((n) => n.id), edges);

  const query = filters.search.trim().toLowerCase();
  const highlighted = new Set<string>(query ? nodes.filter((n) => n.id.toLowerCase().includes(query)).map((n) => n.id) : []);

  const packages = new Map<string, string[]>();
  if (filters.groupByPackage) {
    for (const n of nodes) {
      if (n.package) packages.set(n.package, [...(packages.get(n.package) ?? []), n.id]);
    }
    // A package with a single target doesn't need a box.
    for (const [name, members] of packages) if (members.length < 2) packages.delete(name);
  }

  return { nodes, edges, packages, highlighted, depths, isolated, transitiveHidden };
}

export function dependents(graph: Graph, id: string): string[] {
  return [...new Set(graph.edges.filter((e) => e.to === id).map((e) => e.from))].sort();
}

export function dependencies(graph: Graph, id: string): string[] {
  return [...new Set(graph.edges.filter((e) => e.from === id).map((e) => e.to))].sort();
}

/** Depth of every node: 0 for leaves, otherwise 1 + the deepest dependency (longest path). Cycles get the depth reached so far. */
export function layerDepths(nodeIds: string[], edges: { from: string; to: string }[]): Map<string, number> {
  const ids = new Set(nodeIds);
  const out = new Map<string, string[]>();
  for (const e of edges) if (ids.has(e.from) && ids.has(e.to)) out.set(e.from, [...(out.get(e.from) ?? []), e.to]);
  const depth = new Map<string, number>();
  const visiting = new Set<string>();
  const visit = (id: string): number => {
    const known = depth.get(id);
    if (known != null) return known;
    if (visiting.has(id)) return 0;
    visiting.add(id);
    let d = 0;
    for (const dep of out.get(id) ?? []) d = Math.max(d, visit(dep) + 1);
    visiting.delete(id);
    depth.set(id, d);
    return d;
  };
  for (const id of nodeIds) visit(id);
  return depth;
}

/** Remove every edge A→C when another path A→…→C exists. */
export function transitiveReduction<E extends { from: string; to: string }>(edges: E[]): E[] {
  const out = new Map<string, Set<string>>();
  for (const e of edges) out.set(e.from, (out.get(e.from) ?? new Set()).add(e.to));
  const reachCache = new Map<string, Set<string>>();
  const reach = (id: string, stack = new Set<string>()): Set<string> => {
    const cached = reachCache.get(id);
    if (cached) return cached;
    if (stack.has(id)) return new Set();
    stack.add(id);
    const result = new Set<string>();
    for (const next of out.get(id) ?? []) {
      result.add(next);
      for (const r of reach(next, stack)) result.add(r);
    }
    stack.delete(id);
    reachCache.set(id, result);
    return result;
  };
  return edges.filter((e) => {
    for (const mid of out.get(e.from) ?? []) {
      if (mid !== e.to && reach(mid).has(e.to)) return false;
    }
    return true;
  });
}
