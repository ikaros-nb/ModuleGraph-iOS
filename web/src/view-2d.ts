import cytoscape, { type Core } from "cytoscape";
import fcose from "cytoscape-fcose";
import type { LayoutMode, ViewModel } from "./graph-model";
import { edgeColors, kindColors, labelColor, onColorSchemeChange } from "./theme";

type Position = { x: number; y: number };

cytoscape.use(fcose);

export class View2D {
  private cy: Core;
  private onSelect: (id: string | null) => void;

  constructor(container: HTMLElement, onSelect: (id: string | null) => void) {
    this.onSelect = onSelect;
    this.cy = cytoscape({
      container,
      wheelSensitivity: 0.3,
      style: [
        {
          selector: "node",
          style: {
            label: "data(label)",
            "background-color": "data(color)",
            color: labelColor(),
            "font-size": 18,
            "text-valign": "bottom",
            "text-margin-y": 6,
            width: "data(size)",
            height: "data(size)",
            "border-width": 0,
          },
        },
        {
          selector: "node.ring",
          style: {
            shape: "ellipse", "background-opacity": 0, "border-width": 1, "border-style": "dashed", "border-color": "#8a94a6", "border-opacity": 0.35,
            label: "data(label)", "text-valign": "top", "text-margin-y": 14, "font-size": 10, color: "#8a94a6", "z-index": 0, events: "no",
          },
        },
        { selector: "node:parent", style: { "background-opacity": 0.08, "border-width": 1, "border-color": "#8a94a6", "text-valign": "top", "font-size": 12, "font-weight": "bold" } },
        { selector: "node.highlight", style: { "border-width": 3, "border-color": "#ffcc00" } },
        { selector: "node:selected", style: { "border-width": 3, "border-color": "#ff6b6b" } },
        { selector: "node.dim", style: { opacity: 0.2 } },
        { selector: "edge.dim", style: { opacity: 0.08 } },
        {
          selector: "edge",
          style: {
            "curve-style": "bezier",
            "target-arrow-shape": "triangle",
            "line-color": "data(color)",
            "target-arrow-color": "data(color)",
            width: "data(width)",
            "arrow-scale": 0.8,
            opacity: 0.8,
          },
        },
        { selector: "edge[status = 'import-only']", style: { "line-style": "dashed" } },
      ],
    });
    this.cy.on("tap", "node", (event) => {
      const node = event.target;
      if (node.isParent()) return;
      this.onSelect(node.id());
    });
    this.cy.on("tap", (event) => {
      if (event.target === this.cy) this.onSelect(null);
    });
    this.cy.on("mouseover", "node", (event) => {
      if (this.cy.$(":selected").nonempty() || event.target.isParent()) return;
      const hood = event.target.closedNeighborhood();
      this.cy.elements().not(hood).not(":parent").not(".ring").addClass("dim");
    });
    this.cy.on("mouseout", "node", () => {
      if (this.cy.$(":selected").nonempty()) return;
      this.cy.elements().removeClass("dim");
    });
    onColorSchemeChange(() => this.cy.style().selector("node").style("color", labelColor()).update());
  }

  /** What the last render laid out: a render that changes none of it only restyles. */
  private topology = "";

  private ringGuides: { id: string; label: string; radius: number }[] = [];

  private layoutOptions(vm: ViewModel, layout: LayoutMode, seeded: boolean): object {
    const maxDepth = Math.max(0, ...vm.depths.values());
    this.ringGuides = [];
    switch (layout) {
      case "onion": {
        // Rings by depth: leaves in the centre, the app outside. Each ring is rotated so that
        // single-node rings don't line up, and the radius grows with the ring's population.
        const rings = new Map<number, string[]>();
        for (const n of vm.nodes) rings.set(vm.depths.get(n.id) ?? 0, [...(rings.get(vm.depths.get(n.id) ?? 0) ?? []), n.id]);
        const positions: Record<string, { x: number; y: number }> = {};
        let radius = 0;
        for (let depth = 0; depth <= maxDepth; depth++) {
          const ids = (rings.get(depth) ?? []).sort();
          if (ids.length === 0) continue;
          const needed = (ids.length * 150) / (2 * Math.PI);
          radius = depth === 0 && ids.length === 1 ? 0 : Math.max(radius + 150, needed);
          if (radius > 0) this.ringGuides.push({ id: `ring:${depth}`, label: `Layer ${depth}`, radius });
          const offset = depth * 0.9;
          ids.forEach((id, i) => {
            const angle = offset + (2 * Math.PI * i) / ids.length - Math.PI / 2;
            positions[id] = { x: radius * Math.cos(angle), y: radius * Math.sin(angle) };
          });
        }
        return { name: "preset", animate: false, padding: 40, positions: (node: { id(): string }) => positions[node.id()] };
      }
      case "layers": {
        // One row per depth, the app on top and the leaves at the bottom.
        const rows = new Map<number, string[]>();
        for (const n of vm.nodes) rows.set(vm.depths.get(n.id) ?? 0, [...(rows.get(vm.depths.get(n.id) ?? 0) ?? []), n.id]);
        const widest = Math.max(1, ...[...rows.values()].map((r) => r.length));
        const positions: Record<string, { x: number; y: number }> = {};
        for (const [depth, ids] of rows) {
          ids.sort();
          const step = (widest * 180) / (ids.length + 1);
          ids.forEach((id, i) => {
            positions[id] = { x: step * (i + 1), y: (maxDepth - depth) * 180 };
          });
        }
        return { name: "preset", animate: false, padding: 40, positions: (node: { id(): string }) => positions[node.id()] };
      }
      default:
        // Seeded from the previous Force positions when there are some, so that toggling a filter doesn't reshuffle the graph.
        return { name: "fcose", animate: false, nodeSeparation: 120, idealEdgeLength: () => 140, nodeRepulsion: () => 9000, randomize: !seeded };
    }
  }

  render(vm: ViewModel, layout: LayoutMode = "onion") {
    const compound = layout === "force";
    const topology = JSON.stringify([
      layout,
      compound ? [...vm.packages] : [],
      vm.nodes.map((n) => [n.id, n.kind, n.sourceFiles]),
      vm.edges.map((e) => [e.from, e.to, e.status, e.count]),
    ]);
    if (topology === this.topology) {
      this.cy.nodes(".highlight").removeClass("highlight");
      this.cy.nodes().filter((n) => vm.highlighted.has(n.id())).addClass("highlight");
      return;
    }
    const seeds = compound && this.topology.startsWith('["force"') ? this.seedPositions(vm) : null;
    this.topology = topology;
    const elements = [
      ...(compound ? [...vm.packages.keys()] : []).map((name) => ({ data: { id: `pkg:${name}`, label: name, color: "#8a94a6", size: 1 } })),
      ...vm.nodes.map((n) => {
        const parent = compound && vm.packages.has(n.package ?? "") ? `pkg:${n.package}` : undefined;
        return {
          data: {
            id: n.id,
            label: n.id,
            color: kindColors[n.kind],
            size: 24 + Math.min(40, Math.sqrt(n.sourceFiles ?? 4) * 5),
            parent,
          },
          classes: vm.highlighted.has(n.id) ? "highlight" : "",
          position: seeds?.get(n.id),
        };
      }),
      ...vm.edges.map((e) => ({
        data: {
          id: `${e.from}->${e.to}`,
          source: e.from,
          target: e.to,
          color: edgeColors[e.status],
          status: e.status,
          width: 1 + Math.min(5, Math.log2(1 + e.count)),
        },
      })),
    ];
    const options = this.layoutOptions(vm, layout, seeds != null);
    this.cy.elements().remove();
    this.cy.add(elements);
    if (layout === "onion") {
      this.cy.add(this.ringGuides.map((r) => ({ data: { id: r.id, label: r.label, color: "transparent", size: r.radius * 2 }, classes: "ring", position: { x: 0, y: 0 }, selectable: false, grabbable: false })));
    }
    this.cy.layout({ ...options, eles: this.cy.nodes().not(".ring") } as never).run();
    this.cy.nodes(".ring").positions({ x: 0, y: 0 });
    this.cy.fit(undefined, 40);
  }

  /** Current positions for the nodes already shown, next to a neighbour for the new ones. Null when most nodes are new. */
  private seedPositions(vm: ViewModel): Map<string, Position> | null {
    const previous = new Map<string, Position>();
    this.cy.nodes().not(".ring").not(":parent").forEach((n) => void previous.set(n.id(), { ...n.position() }));
    if (vm.nodes.filter((n) => previous.has(n.id)).length < vm.nodes.length / 2) return null;
    const seeds = new Map<string, Position>();
    for (const n of vm.nodes) {
      const known = previous.get(n.id);
      if (known) {
        seeds.set(n.id, known);
        continue;
      }
      const neighbour = vm.edges.map((e) => (e.from === n.id ? e.to : e.to === n.id ? e.from : "")).find((id) => previous.has(id));
      const anchor = (neighbour && previous.get(neighbour)) || { x: 0, y: 0 };
      seeds.set(n.id, { x: anchor.x + (Math.random() - 0.5) * 120, y: anchor.y + (Math.random() - 0.5) * 120 });
    }
    return seeds;
  }

  select(id: string | null) {
    this.cy.elements().removeClass("dim");
    this.cy.$(":selected").unselect();
    if (!id) return;
    const node = this.cy.$id(id);
    if (node.empty()) return;
    node.select();
    const hood = node.closedNeighborhood();
    this.cy.elements().not(hood).not(":parent").not(".ring").addClass("dim");
  }

  fit() {
    this.cy.fit(undefined, 40);
  }

  resize() {
    this.cy.resize();
  }
}
