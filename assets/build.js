import { build } from "esbuild";
import { readFileSync, writeFileSync } from "node:fs";

const outdir = "../lib/assets/cell/build";

const { metafile } = await build({
  entryPoints: ["js/main.js"],
  bundle: true,
  minify: true,
  format: "esm",
  outdir,
  metafile: true,
});

// The bundle contains these packages, so their licenses ship with it.
const packages = new Set(
  Object.keys(metafile.inputs).flatMap((input) => {
    const match = input.match(/node_modules\/((?:@[^/]+\/)?[^/]+)/);
    return match ? [match[1]] : [];
  }),
);

const notices = [...packages].sort().map((name) => {
  const dir = `node_modules/${name}`;
  const { version } = JSON.parse(readFileSync(`${dir}/package.json`, "utf8"));
  return `${name} ${version}\n\n${readFileSync(`${dir}/LICENSE`, "utf8").trim()}\n`;
});

writeFileSync(`${outdir}/THIRD_PARTY_LICENSES.txt`, notices.join("\n---\n\n"));
