import { build } from "esbuild"
import { mkdir, writeFile } from "node:fs/promises"
import { fileURLToPath } from "node:url"

// Some dependency completion snippets contain whitespace-only physical lines.
// Normalize line endings so the checked-in generated bundles pass diff checks
// and are byte-for-byte reproducible through `npm run build`.
async function bundle(entry, output, options = {}) {
  const result = await build({
    entryPoints: [fileURLToPath(new URL(entry, import.meta.url))],
    bundle: true,
    minify: true,
    format: "iife",
    write: false,
    ...options,
  })
  const outputURL = new URL(output, import.meta.url)
  await mkdir(new URL(".", outputURL), { recursive: true })
  await writeFile(outputURL, result.outputFiles[0].text.replace(/[ \t]+$/gm, ""))
}

await bundle("entry-cm.js", "../../md-preview/Vendor/CodeMirror/mdedit.min.js")
// The floorball renderer on its own, as `var MdFloorball`: Swift runs it in
// JavaScriptCore to draw read-mode, export, and Quick Look diagrams.
await bundle("floorball/index.js", "../../md-preview/Vendor/Floorball/floorball.min.js", { globalName: "MdFloorball" })
