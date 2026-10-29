import Ajv2020 from "ajv/dist/2020";
import addFormats from "ajv-formats";
import schema from "./graph.schema.json";
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

export async function fetchGraph(url: string): Promise<Graph> {
  const response = await fetch(url);
  if (!response.ok) throw new GraphError(`Cannot fetch ${url}: ${response.status}`);
  return parseGraph(await response.text());
}

const STORAGE_KEY = "modulegraph:last";

export function rememberGraph(text: string) {
  try {
    localStorage.setItem(STORAGE_KEY, text);
  } catch {
    /* storage unavailable */
  }
}

export function recallGraph(): Graph | null {
  try {
    const text = localStorage.getItem(STORAGE_KEY);
    return text ? parseGraph(text) : null;
  } catch {
    return null;
  }
}
