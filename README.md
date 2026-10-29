# ModuleGraph

Visualise the module graph of an iOS codebase: a Swift CLI scans the project locally and writes a JSON file, and a static web page renders that file as a 2D graph. The source code never leaves your machine, only the JSON does.

```
modulegraph scan ~/Projects/MyApp --output graph.json
```

Then open the web app and drop `graph.json` on it.

## CLI (`cli/`)

Requires a Swift toolchain (6.0 or later), because manifests are read with `swift package dump-package`.

```sh
cd cli
swift build -c release
cp .build/release/modulegraph /usr/local/bin/
```

```
modulegraph scan [<root>] [--output <file>] [--no-imports] [--include-tests] [--pretty]
```

What it reads:

- Every `Package.swift` under the root, through `swift package dump-package`. Each target becomes a node, product dependencies are resolved to the targets that provide them, and remote packages become `external` nodes.
- Every `*.xcodeproj`, both the `project.pbxproj` and the newer `project.xcproj` format. Each native target becomes a node linked to the package products it depends on; a product that no local package provides is an `external` node. Sources come from the Xcode 16 folders, or from the Sources build phase in projects with classic groups.
- Every `import` statement of the Swift sources of each target (skip with `--no-imports`), which gives the effective graph next to the declared one. Apple frameworks are reported as `system` nodes.

Folders such as `.build`, `DerivedData`, `Pods`, `node_modules` and the simple entries of the root `.gitignore` are skipped. Every path in the output is relative to the root.

## Web (`web/`)

```sh
cd web
npm install
npm run dev
```

A single page, no backend. Open a file, drop one, click the example, or pass `?url=` with a hosted JSON (a raw gist works). The last file is kept in `localStorage`.

- **Layouts**: *Onion* (rings by depth, the leaves in the centre and the app outside), *Layers* (one row per depth, the app on top), and *Force* (fcose, with optional grouping by package). Nodes are coloured by kind.
- **Hide transitive** removes an edge A→C when a path A→…→C already exists, and **Hide isolated** removes the modules left without a visible edge.
- **Edges**: declared, imports, both, or *gaps*: declared but never imported (probably unused) in orange, imported but not declared (reached transitively) dashed red.
- Hide tests, system frameworks and external packages, focus on one module and its neighbours at N hops, search, detail panel with dependencies and dependents.

`npm test` runs the view-model tests and `npm run build` type-checks and produces `dist/`: both run on every pull request (`.github/workflows/web.yml`), and `dist/` is deployed to GitHub Pages by `.github/workflows/pages.yml`.

## JSON format

The schema is in `schema/graph.schema.json`. `SampleApp/` is a small made-up project and `SampleApp/graph.json` its output: the CLI tests check that a scan still produces it, and the web app loads it as the example.

```json
{
  "version": 1,
  "project": "SampleApp",
  "generatedAt": "2026-10-16T13:00:00Z",
  "nodes": [
    { "id": "Domain", "kind": "library", "package": "Domain", "group": "Packages", "path": "Packages/Domain/Sources/Domain", "sourceFiles": 21 }
  ],
  "edges": [
    { "from": "Domain", "to": "Toolkit", "kind": "declared" },
    { "from": "Domain", "to": "Toolkit", "kind": "import", "count": 7 }
  ],
  "warnings": [ { "code": "manifest-dump-failed", "path": "Packages/Broken", "message": "…" } ]
}
```

Node kinds: `app`, `library`, `test`, `executable`, `macro`, `system`, `external`. Edge kinds: `declared`, `import`.

## Limits (V1)

- A `Package.swift` that computes its dependencies from the environment is dumped in the current environment only.
- `import` statements inside `/* */` comments are counted.
- Tuist, CocoaPods and Carthage are not read. An external SwiftPM package is a leaf, its own graph is not scanned.
- The import scan reads Xcode 16 synchronized folders whole: a file excluded from a target but kept in its folder is still counted.
