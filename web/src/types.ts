export type NodeKind = "app" | "library" | "test" | "executable" | "macro" | "system" | "external";
export type EdgeKind = "declared" | "import";

export interface GraphNode {
  id: string;
  kind: NodeKind;
  package?: string;
  group?: string;
  path?: string;
  sourceFiles?: number;
}

export interface GraphEdge {
  from: string;
  to: string;
  kind: EdgeKind;
  count?: number;
}

export interface GraphWarning {
  code: string;
  path?: string;
  message: string;
}

export interface Graph {
  version: 1;
  project: string;
  root?: string;
  generatedAt?: string;
  nodes: GraphNode[];
  edges: GraphEdge[];
  warnings?: GraphWarning[];
}
