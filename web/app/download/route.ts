const repo = "https://github.com/thecmdrunner/gust";

export async function GET() {
  try {
    const response = await fetch("https://api.github.com/repos/thecmdrunner/gust/releases/latest", {
      headers: { Accept: "application/vnd.github+json" },
      next: { revalidate: 60 },
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error("Release unavailable");
    const release = await response.json();
    const version = String(release.tag_name).replace(/^v/, "");
    if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error("Invalid version");
    const assets = release.assets as { name: string; browser_download_url: string }[];
    const asset = assets.find((a) => a.name === `Gust-${version}-macos.dmg`)
      ?? assets.find((a) => a.name === "Gust.dmg");
    if (!asset?.browser_download_url.startsWith(`${repo}/releases/download/`)) throw new Error("Installer unavailable");
    return Response.redirect(asset.browser_download_url, 307);
  } catch {
    return Response.redirect(`${repo}/releases/latest`, 307);
  }
}
