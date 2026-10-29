import "./style.css";
import { buildViewModel, defaultFilters, dependencies, dependents, type EdgeMode, type Filters, type LayoutMode, type ViewModel } from "./graph-model";
import { type Child, h } from "./dom";
import { fetchGraphText, forgetGraph, GraphError, parseGraph, recallGraph, rememberGraph } from "./load";
import type { Graph } from "./types";
import { View2D } from "./view-2d";
import { edgeColors, edgeLabels, kindColors } from "./theme";

const $ = <T extends HTMLElement>(selector: string) => document.querySelector<T>(selector)!;

let graph: Graph | null = null;
let filters: Filters = { ...defaultFilters };
let selected: string | null = null;
/** Modules on screen: the detail panel links only to those. */
let visible = new Set<string>();

const dropzone = $("#dropzone");
const app = $("#app");
const stage = $("#stage-2d");
const errorBox = $("#error");

const view = new View2D(stage, select);

let errorTimer: number | undefined;
function showError(message: string) {
  errorBox.textContent = message;
  errorBox.hidden = false;
  clearTimeout(errorTimer);
  errorTimer = window.setTimeout(() => (errorBox.hidden = true), 8000);
}

/**
 * Parse and show a graph file. Returns false, after showing the error, when it isn't one: the graph on
 * screen stays when the file doesn't parse, and the dropzone comes back when it parses but can't be drawn.
 * A hosted graph isn't remembered: its URL brings it back, and the user's own last file is kept.
 */
function load(text: string, remember = true): boolean {
  let parsed: Graph;
  try {
    parsed = parseGraph(text);
  } catch (error) {
    showError(error instanceof GraphError ? error.message : String(error));
    return false;
  }
  graph = parsed;
  selected = null;
  filters = { ...defaultFilters, edgeMode: graph.edges.some((e) => e.kind === "import") ? "both" : "declared" };
  renderFocusOptions();
  renderWarnings();
  syncControls();
  dropzone.hidden = true;
  app.hidden = false;
  try {
    render();
  } catch (error) {
    graph = null;
    app.hidden = true;
    dropzone.hidden = false;
    showError(`Cannot draw this graph: ${error instanceof Error ? error.message : String(error)}`);
    return false;
  }
  // Only a file that rendered is kept: a stored one is shown again on every visit.
  if (remember) rememberGraph(text);
  return true;
}

function render() {
  if (!graph) return;
  const vm = buildViewModel(graph, filters);
  visible = new Set(vm.nodes.map((n) => n.id));
  const extras = [
    vm.transitiveHidden ? `${vm.transitiveHidden} transitive hidden` : "",
    vm.isolated.length ? `${vm.isolated.length} isolated hidden` : "",
  ].filter(Boolean);
  $("#stats").textContent = `${graph.project} · ${vm.nodes.length} modules · ${vm.edges.length} edges${extras.length ? ` · ${extras.join(", ")}` : ""}`;
  $("#stats").title = vm.isolated.length ? `Isolated: ${vm.isolated.join(", ")}` : "";
  view.resize();
  view.render(vm, filters.layout);
  view.select(selected);
  renderLegend(vm);
  renderDetail();
}

// Panels are built with DOM APIs: values from the file only ever become text or attributes.
function renderLegend(vm: ViewModel) {
  const kinds = new Set(vm.nodes.map((n) => n.kind));
  const statuses = new Set(vm.edges.map((e) => e.status));
  const nodeItems = Object.entries(kindColors)
    .filter(([kind]) => kinds.has(kind as keyof typeof kindColors))
    .map(([kind, color]) => h("span", {}, h("i", { class: "dot", style: `background:${color}` }), kind));
  const edgeItems = Object.entries(edgeLabels)
    .filter(([status]) => statuses.has(status as keyof typeof edgeLabels))
    .map(([status, label]) => {
      const style = `border-top-color:${edgeColors[status as keyof typeof edgeColors]}${status === "import-only" ? ";border-top-style:dashed" : ""}`;
      return h("span", {}, h("i", { class: "line", style }), label);
    });
  $("#legend").replaceChildren(...nodeItems, ...edgeItems);
}

function select(id: string | null) {
  selected = id;
  view.select(id);
  renderDetail();
}

function button(label: string, onClick: () => void, attributes: Record<string, string> = {}) {
  const element = h("button", attributes, label);
  element.addEventListener("click", onClick);
  return element;
}

function renderDetail() {
  const panel = $("#detail");
  const node = graph && selected ? graph.nodes.find((n) => n.id === selected) : undefined;
  panel.hidden = !node;
  if (!graph || !node) return;
  // A module hidden by the filters can't be selected on the graph: it is listed as plain text.
  const item = (id: string) =>
    h("li", {}, visible.has(id) ? button(id, () => select(id), { class: "link" }) : h("span", { class: "muted", title: "Hidden by the current filters" }, id));
  const list = (ids: string[]) => h("ul", {}, ...(ids.length ? ids.map(item) : [h("li", { class: "muted" }, "none")]));
  const field = (label: string, value: Child) => (value == null || value === "" ? [] : [h("dt", {}, label), h("dd", {}, value)]);
  const uses = dependencies(graph, node.id);
  const usedBy = dependents(graph, node.id);
  panel.replaceChildren(
    h("header", {}, h("span", { class: "dot", style: `background:${kindColors[node.kind]}` }), h("h2", {}, node.id), button("×", () => select(null), { "aria-label": "Close" })),
    h(
      "dl",
      {},
      ...field("Kind", node.kind),
      ...field("Package", node.package),
      ...field("Group", node.group),
      ...field("Path", node.path && h("code", {}, node.path)),
      ...field("Swift files", node.sourceFiles),
    ),
    h("h3", {}, `Depends on (${uses.length})`),
    list(uses),
    h("h3", {}, `Used by (${usedBy.length})`),
    list(usedBy),
    button("Focus on this module", () => {
      filters.focus = node.id;
      syncControls();
      render();
    }),
  );
}

function renderWarnings() {
  const box = $("#warnings");
  const warnings = graph?.warnings ?? [];
  box.hidden = warnings.length === 0;
  box.replaceChildren(
    h("summary", {}, `${warnings.length} warning${warnings.length > 1 ? "s" : ""}`),
    h("ul", {}, ...warnings.map((w) => h("li", {}, h("code", {}, w.code), " ", w.path && h("code", {}, w.path), w.path && " ", w.message))),
  );
}

function renderFocusOptions() {
  const ids = graph?.nodes.map((n) => n.id) ?? [];
  $("#focus").replaceChildren(h("option", { value: "" }, "Whole graph"), ...ids.map((id) => h("option", { value: id }, id)));
}

function syncControls() {
  $<HTMLInputElement>("#show-tests").checked = filters.showTests;
  $<HTMLInputElement>("#show-system").checked = filters.showSystem;
  $<HTMLInputElement>("#show-external").checked = filters.showExternal;
  $<HTMLInputElement>("#group-packages").checked = filters.groupByPackage;
  $<HTMLSelectElement>("#edge-mode").value = filters.edgeMode;
  $<HTMLSelectElement>("#layout").value = filters.layout;
  $<HTMLSelectElement>("#focus").value = filters.focus ?? "";
  $<HTMLInputElement>("#hide-transitive").checked = filters.hideTransitive;
  $<HTMLInputElement>("#hide-isolated").checked = filters.hideIsolated;
  $<HTMLInputElement>("#group-packages").disabled = filters.layout !== "force";
  $<HTMLInputElement>("#search").value = filters.search;
  $<HTMLInputElement>("#focus-depth").value = String(filters.focusDepth);
  $("#focus-depth-value").textContent = String(filters.focusDepth);
  const hasImports = graph?.edges.some((e) => e.kind === "import") ?? false;
  $<HTMLSelectElement>("#edge-mode").querySelectorAll("option").forEach((o) => (o.disabled = !hasImports && o.value !== "declared"));
}

// Controls
$("#layout").addEventListener("change", (e) => ((filters.layout = (e.target as HTMLSelectElement).value as LayoutMode), syncControls(), render()));
$("#hide-transitive").addEventListener("change", (e) => ((filters.hideTransitive = (e.target as HTMLInputElement).checked), render()));
$("#hide-isolated").addEventListener("change", (e) => ((filters.hideIsolated = (e.target as HTMLInputElement).checked), render()));
$("#show-tests").addEventListener("change", (e) => ((filters.showTests = (e.target as HTMLInputElement).checked), render()));
$("#show-external").addEventListener("change", (e) => ((filters.showExternal = (e.target as HTMLInputElement).checked), render()));
$("#show-system").addEventListener("change", (e) => ((filters.showSystem = (e.target as HTMLInputElement).checked), render()));
$("#group-packages").addEventListener("change", (e) => ((filters.groupByPackage = (e.target as HTMLInputElement).checked), render()));
$("#edge-mode").addEventListener("change", (e) => ((filters.edgeMode = (e.target as HTMLSelectElement).value as EdgeMode), render()));
$("#focus").addEventListener("change", (e) => ((filters.focus = (e.target as HTMLSelectElement).value || null), render()));
$("#focus-depth").addEventListener("input", (e) => {
  filters.focusDepth = Number((e.target as HTMLInputElement).value);
  $("#focus-depth-value").textContent = String(filters.focusDepth);
  render();
});
let searchTimer: number;
$("#search").addEventListener("input", (e) => {
  clearTimeout(searchTimer);
  searchTimer = window.setTimeout(() => ((filters.search = (e.target as HTMLInputElement).value), render()), 150);
});
$("#fit").addEventListener("click", () => view.fit());
$("#open-other").addEventListener("click", () => $<HTMLInputElement>("#file").click());
$("#file").addEventListener("change", async (e) => {
  const file = (e.target as HTMLInputElement).files?.[0];
  if (file) load(await file.text());
  (e.target as HTMLInputElement).value = "";
});
$("#pick-file").addEventListener("click", () => $<HTMLInputElement>("#file").click());
$("#load-example").addEventListener("click", async () => {
  try {
    // The CLI output for SampleApp/, bundled as its own chunk.
    const { default: text } = await import("../../SampleApp/graph.json?raw");
    load(text);
  } catch (error) {
    showError(String(error));
  }
});

document.body.addEventListener("dragover", (e) => {
  e.preventDefault();
  dropzone.classList.add("over");
});
// dragleave also fires when moving over a child element: only leaving the window counts.
document.body.addEventListener("dragleave", (e) => {
  if (!e.relatedTarget) dropzone.classList.remove("over");
});
document.body.addEventListener("drop", async (e) => {
  e.preventDefault();
  dropzone.classList.remove("over");
  const file = e.dataTransfer?.files?.[0];
  if (file) load(await file.text());
});

window.addEventListener("resize", () => view.resize());

// Startup: ?url=, then last file, else dropzone.
const urlParam = new URLSearchParams(location.search).get("url");
if (urlParam) {
  fetchGraphText(urlParam)
    .then((text) => load(text, false))
    .catch((error) => showError(error instanceof Error ? error.message : String(error)));
} else {
  const last = recallGraph();
  // A stored file that no longer parses would fail on every visit.
  if (last && !load(last)) forgetGraph();
}
