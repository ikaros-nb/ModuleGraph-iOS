# SampleApp

A small, made-up project for `modulegraph` to scan. It is never compiled: only its manifests, its project file and the `import` statements of its sources matter. `graph.json` is the CLI output for it; the CLI tests compare a fresh scan against it, the web tests load it, and the viewer offers it as the example.

After changing the sample or the CLI output, regenerate it from `cli/`:

```sh
swift run modulegraph scan ../SampleApp --include-tests --pretty --output ../SampleApp/graph.json
```
