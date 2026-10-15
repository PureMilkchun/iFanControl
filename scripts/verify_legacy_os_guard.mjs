// Exercises the actual Pages worker module with local, immutable ASSETS.
// No network, native application, fan command, or database is used.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const [workerPath, assetsPath] = process.argv.slice(2);
assert(workerPath && assetsPath, "usage: node scripts/verify_legacy_os_guard.mjs worker.mjs site-directory");
const { default: worker } = await import(pathToFileURL(path.resolve(workerPath)).href);
const root = path.resolve(assetsPath);
const frozen = fs.readFileSync(path.join(root, "update-manifest.json"));
let assetReads = 0;
const env = { ASSETS: { async fetch(request) {
    assetReads++;
    const name = new URL(request.url).pathname.slice(1);
    const file = path.resolve(root, name);
    if (!file.startsWith(root + path.sep) || !fs.existsSync(file)) return new Response(null, { status: 404 });
    return new Response(request.method === "HEAD" ? null : fs.readFileSync(file), {
        headers: { "Content-Type": name.endsWith(".json") ? "application/json" : "application/octet-stream" }
    });
} } };
const ctx = { waitUntil() {}, passThroughOnException() {} };
let cases = 0;
const pausedAgents = [
    "MacFanControl/44 CFNetwork/1496 Darwin/23.6.0", // macOS 14
    "MacFanControl/35 CFNetwork/1408 Darwin/22.6.0", // macOS 13
    "iFanControl/50 CFNetwork/3826", // unknown kernel
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
    "curl/8.0", "", "iFanControl/50 CFNetwork/1 Darwin/999999.1"
];
for (const agent of pausedAgents) {
    const reads = assetReads;
    const response = await worker.fetch(new Request("https://example.test/update-manifest.json", {
        headers: agent ? { "User-Agent": agent } : {}
    }), env, ctx);
    const manifest = await response.json();
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("Cache-Control"), "no-store");
    assert.equal(response.headers.get("Vary"), "User-Agent");
    assert.equal(manifest.latest_build, 0);
    assert.equal(manifest.assets, null);
    for (const localBuild of [0, 1, 35, 44, 50]) assert(manifest.latest_build <= localBuild);
    assert.equal(assetReads, reads, "paused request must not fall through to unsafe manifest");
    cases++;
}
for (const agent of ["iFanControl/50 CFNetwork/3826 Darwin/24.2.0", "iFanControl/50 CFNetwork/3860 Darwin/25.0.0", "MacFanControl/44 CFNetwork/1 Darwin/26.1.0"]) {
    const response = await worker.fetch(new Request("https://example.test/update-manifest.json", {
        headers: { "User-Agent": agent }
    }), env, ctx);
    assert.equal(response.headers.get("Cache-Control"), "no-store");
    assert.equal(response.headers.get("Vary"), "User-Agent");
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), frozen);
    cases++;
}
for (const name of ["update-manifest-pkg.json", "update-manifest-beta.json", "iFanControl-legacy-2.9.9.zip", "iFanControl-macOS.zip"]) {
    const response = await worker.fetch(new Request("https://example.test/" + name, {
        headers: { "User-Agent": pausedAgents[0] }
    }), env, ctx);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), fs.readFileSync(path.join(root, name)));
    cases++;
}
for (const name of ["update-manifest.json", "download"]) {
    const response = await worker.fetch(new Request("https://example.test/" + name, {
        method: "HEAD", headers: { "User-Agent": pausedAgents[0] }
    }), env, ctx);
    assert.equal(await response.text(), "");
    if (name === "download") {
        assert.equal(response.status, 302);
        const location = new URL(response.headers.get("Location"));
        assert.equal(location.pathname, "/iFanControl-macOS.pkg");
        assert.equal(location.searchParams.get("build"), "71");
    } else assert.equal(response.status, 200);
    cases++;
}
console.log(`PASS: ${cases} actual worker cases; unsupported/unknown OS blocked, supported bridge byte-exact, native feeds/ZIPs/download unchanged.`);
