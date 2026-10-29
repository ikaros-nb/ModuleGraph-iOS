import "./style.css";
import { buildViewModel, defaultFilters, dependencies, dependents, type EdgeMode, type Filters, type LayoutMode } from "./graph-model";
import { escapeHtml as esc } from "./html";
import { fetchGraph, GraphError, parseGraph, recallGraph, rememberGraph } from "./load";
import type { Graph } from "./types";
import { View2D } from "./view-2d";
import { kindColors } from "./theme";

const $ = <T extends HTMLElement>(selector: string) => document.querySelector<T>(selector)!;

let graph: Graph | null = null;
let filters: Filters = { ...defaultFilters };
let selected: string | null = null;

const dropzone = $("#dropzone");
const app = $("#app");
const stage = $("#stage-2d");
const errorBox = $("#error");

const view = new View2D(stage, select);

function showError(message: string) {
  errorBox.textContent = message;
  errorBox.hidden = false;
  setTimeout(() => (errorBox.hidden = true), 8000);
}

function load(text: string) {
  try {
    graph = parseGraph(text);
    rememberGraph(text);
    selected = null;
    filters = { ...defaultFilters, edgeMode: graph.edges.some((e) => e.kind === "import") ? "both" : "declared" };
    syncControls();
    dropzone.hidden = true;
    app.hidden = false;
    render();
  } catch (error) {
    showError(error instanceof GraphError ? error.message : String(error));
  }
}

function render() {
  if (!graph) return;
  const vm = buildViewModel(graph, filters);
  const extras = [
    vm.transitiveHidden ? `${vm.transitiveHidden} transitive hidden` : "",
    vm.isolated.length ? `${vm.isolated.length} isolated hidden` : "",
  ].filter(Boolean);
  $("#stats").textContent = `${graph.project} · ${vm.nodes.length} modules · ${vm.edges.length} edges${extras.length ? ` · ${extras.join(", ")}` : ""}`;
  $("#stats").title = vm.isolated.length ? `Isolated: ${vm.isolated.join(", ")}` : "";
  view.resize();
  view.render(vm, filters.layout);
  view.select(selected);
  renderFocusOptions(vm.nodes.map((n) => n.id));
  renderWarnings();
  renderDetail();
}

function select(id: string | null) {
  selected = id;
  view.select(id);
  renderDetail();
}

function renderDetail() {
  const panel = $("#detail");
  if (!graph || !selected) {
    panel.hidden = true;
    return;
  }
  const node = graph.nodes.find((n) => n.id === selected);
  if (!node) {
    panel.hidden = true;
    return;
  }
  // Every value from the file is escaped: a graph loaded from ?url= is untrusted.
  const list = (ids: string[]) => (ids.length ? ids.map((id) => `<li><button class="link" data-id="${esc(id)}">${esc(id)}</button></li>`).join("") : "<li class='muted'>none</li>");
  panel.hidden = false;
  panel.innerHTML = `
    <header><span class="dot" style="background:${kindColors[node.kind]}"></span><h2>${esc(node.id)}</h2><button id="close-detail" aria-label="Close">×</button></header>
    <dl>
      <dt>Kind</dt><dd>${esc(node.kind)}</dd>
      ${node.package ? `<dt>Package</dt><dd>${esc(node.package)}</dd>` : ""}
      ${node.group ? `<dt>Group</dt><dd>${esc(node.group)}</dd>` : ""}
      ${node.path ? `<dt>Path</dt><dd><code>${esc(node.path)}</code></dd>` : ""}
      ${node.sourceFiles != null ? `<dt>Swift files</dt><dd>${esc(node.sourceFiles)}</dd>` : ""}
    </dl>
    <h3>Depends on (${dependencies(graph, node.id).length})</h3><ul>${list(dependencies(graph, node.id))}</ul>
    <h3>Used by (${dependents(graph, node.id).length})</h3><ul>${list(dependents(graph, node.id))}</ul>
    <button id="focus-node">Focus on this module</button>`;
  panel.querySelector("#close-detail")!.addEventListener("click", () => select(null));
  panel.querySelector("#focus-node")!.addEventListener("click", () => {
    filters.focus = node.id;
    syncControls();
    render();
  });
  panel.querySelectorAll<HTMLButtonElement>("button.link").forEach((b) => b.addEventListener("click", () => select(b.dataset.id!)));
}

function renderWarnings() {
  const box = $("#warnings");
  const warnings = graph?.warnings ?? [];
  box.hidden = warnings.length === 0;
  box.innerHTML = `<summary>${warnings.length} warning${warnings.length > 1 ? "s" : ""}</summary><ul>${warnings
    .map((w) => `<li><code>${esc(w.code)}</code> ${w.path ? `<code>${esc(w.path)}</code> ` : ""}${esc(w.message)}</li>`)
    .join("")}</ul>`;
}

function renderFocusOptions(ids: string[]) {
  const focus = $<HTMLSelectElement>("#focus");
  const all = graph?.nodes.map((n) => n.id) ?? ids;
  focus.innerHTML = `<option value="">Whole graph</option>${all.map((id) => `<option value="${esc(id)}" ${filters.focus === id ? "selected" : ""}>${esc(id)}</option>`).join("")}`;
}

function syncControls() {
  $<HTMLInputElement>("#show-tests").checked = filters.showTests;
  $<HTMLInputElement>("#show-system").checked = filters.showSystem;
  $<HTMLInputElement>("#show-external").checked = filters.showExternal;
  $<HTMLInputElement>("#group-packages").checked = filters.groupByPackage;
  $<HTMLSelectElement>("#edge-mode").value = filters.edgeMode;
  $<HTMLSelectElement>("#layout").value = filters.layout;
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

for (const target of [document.body]) {
  target.addEventListener("dragover", (e) => {
    e.preventDefault();
    dropzone.classList.add("over");
  });
  target.addEventListener("dragleave", () => dropzone.classList.remove("over"));
  target.addEventListener("drop", async (e) => {
    e.preventDefault();
    dropzone.classList.remove("over");
    const file = e.dataTransfer?.files?.[0];
    if (file) load(await file.text());
  });
}

window.addEventListener("resize", () => view.resize());

// Startup: ?url=, then last file, else dropzone.
const urlParam = new URLSearchParams(location.search).get("url");
if (urlParam) {
  fetchGraph(urlParam)
    .then((g) => load(JSON.stringify(g)))
    .catch((error) => showError(String(error)));
} else {
  const last = recallGraph();
  if (last) load(JSON.stringify(last));
}
