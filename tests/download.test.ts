import { afterEach, expect, test } from "bun:test";
import { GET } from "../web/app/download/route";

const originalFetch = globalThis.fetch;
const repo = "https://github.com/thecmdrunner/gust";
afterEach(() => { globalThis.fetch = originalFetch; });
function release(name: string, url = `${repo}/releases/download/v1.1.2/${name}`) {
  globalThis.fetch = (async () => Response.json({ tag_name: "v1.1.2", assets: [{ name, browser_download_url: url }] })) as typeof fetch;
}
test("download resolves the versioned installer", async () => {
  release("Gust-1.1.2-macos.dmg");
  const response = await GET();
  expect(response.status).toBe(307);
  expect(response.headers.get("Location")).toBe(`${repo}/releases/download/v1.1.2/Gust-1.1.2-macos.dmg`);
});
test("legacy releases remain downloadable during rollout", async () => {
  release("Gust.dmg");
  expect((await GET()).headers.get("Location")).toBe(`${repo}/releases/download/v1.1.2/Gust.dmg`);
});
test("missing installer falls back to the release page", async () => {
  release("SHA256SUMS.txt");
  expect((await GET()).headers.get("Location")).toBe(`${repo}/releases/latest`);
});
test("API failure still offers a useful destination", async () => {
  globalThis.fetch = (async () => new Response(null, { status: 503 })) as typeof fetch;
  expect((await GET()).headers.get("Location")).toBe(`${repo}/releases/latest`);
});
test("unexpected download hosts are rejected", async () => {
  release("Gust-1.1.2-macos.dmg", "https://example.com/installer");
  expect((await GET()).headers.get("Location")).toBe(`${repo}/releases/latest`);
});
