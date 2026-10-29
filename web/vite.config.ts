import { defineConfig } from "vite";

export default defineConfig({
  base: process.env.BASE_PATH ?? "/",
  build: { chunkSizeWarningLimit: 1500 },
  // The example is imported from SampleApp/, outside web/.
  server: { fs: { allow: [".."] } },
});
