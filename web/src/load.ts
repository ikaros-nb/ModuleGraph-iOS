import Ajv2020 from "ajv/dist/2020";
import addFormats from "ajv-formats";
// The one schema of the format, shared with the CLI.
import schema from "../../schema/graph.schema.json";
import type { Graph } from "./types";

const ajv = new Ajv2020({ allErrors: true });
addFormats(ajv);
const validate = ajv.compile<Graph>(schema);

export class GraphError extends Error {}

export function parseGraph(text: string): Graph {
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch (error) {
    throw new GraphError(`Not valid JSON: ${(error as Error).message}`);
  }
  if (!validate(json)) {
    const details = (validate.errors ?? [])
      .slice(0, 5)
      .map((e) => `${e.instancePath || "/"} ${e.message ?? ""}`)
      .join("\n");
    throw new GraphError(`Not a ModuleGraph file:\n${details}`);
  }
  const ids = new Set(json.nodes.map((n) => n.id));
  const dangling = json.edges.find((e) => !ids.has(e.from) || !ids.has(e.to));
  if (dangling) throw new GraphError(`Edge ${dangling.from} → ${dangling.to} references an unknown node`);
  return json;
}

/** The text of a hosted graph, parsed by the caller like any other source. */
export async function fetchGraphText(url: string): Promise<string> {
  const response = await fetch(url);
  if (!response.ok) throw new GraphError(`Cannot fetch ${url}: ${response.status}`);
  return response.text();
}

const STORAGE_KEY = "modulegraph:last";

export function rememberGraph(text: string) {
  try {
    localStorage.setItem(STORAGE_KEY, text);
  } catch {
    /* storage unavailable */
  }
}

export function recallGraph(): string | null {
  try {
    return localStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}

export function forgetGraph() {
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
    /* storage unavailable */
  }
}
