import { ImageResponse } from "next/og";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

export const alt = "Gust — Fan control for Mac";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function Image() {
  const [font, icon] = await Promise.all([
    readFile(join(process.cwd(), "assets/InterTight-SemiBold.ttf")),
    readFile(join(process.cwd(), "public/gust-icon.png")),
  ]);
  const iconSrc = `data:image/png;base64,${icon.toString("base64")}`;

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "0 110px",
          background: "radial-gradient(circle at 78% 50%, #10255e 0%, #08090b 60%)",
          color: "#f3f4f6",
          fontFamily: "Inter Tight",
        }}
      >
        <div style={{ display: "flex", flexDirection: "column" }}>
          <div style={{ fontSize: 120, letterSpacing: -5, lineHeight: 1 }}>Gust</div>
          <div style={{ fontSize: 44, letterSpacing: -1.5, marginTop: 28, color: "#f3f4f6" }}>Full blast.</div>
          <div style={{ fontSize: 44, letterSpacing: -1.5, color: "#7d8390" }}>On demand.</div>
          <div style={{ display: "flex", alignItems: "baseline", marginTop: 48, fontSize: 30, color: "#5cc2ff" }}>
            5,777 <span style={{ fontSize: 22, marginLeft: 8, color: "#7d8390" }}>rpm</span>
          </div>
        </div>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={iconSrc} width={400} height={400} alt="" />
      </div>
    ),
    { ...size, fonts: [{ name: "Inter Tight", data: font, weight: 600 }] },
  );
}
