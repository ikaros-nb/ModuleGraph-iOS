import type { NodeKind } from "./types";
import type { ViewEdge } from "./graph-model";

export const kindColors: Record<NodeKind, string> = {
  app: "#e4572e",
  library: "#4f8fe6",
  test: "#9aa5b1",
  executable: "#f2a541",
  macro: "#b36ae2",
  system: "#7f8c8d",
  external: "#2bb673",
};

export const edgeColors: Record<ViewEdge["status"], string> = {
  declared: "#8a94a6",
  import: "#4f8fe6",
  both: "#8a94a6",
  "declared-only": "#f2a541",
  "import-only": "#e4572e",
};

export const isDark = () => window.matchMedia("(prefers-color-scheme: dark)").matches;
