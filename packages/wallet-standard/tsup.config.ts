import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/index.ts"],
  format: ["esm", "cjs"],
  dts: true,
  sourcemap: true,
  clean: true,
  target: "es2022",
  external: [
    "@wallet-association/core",
    "@wallet-association/transport-localhost",
    "@wallet-standard/base",
    "@wallet-standard/features"
  ]
});
