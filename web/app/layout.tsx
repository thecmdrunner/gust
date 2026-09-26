import type { Metadata, Viewport } from "next";
import { Inter_Tight } from "next/font/google";
import "./globals.css";

const interTight = Inter_Tight({ variable: "--font-inter-tight", subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Gust — Fan control for Mac",
  description: "Lock your MacBook fans to max, min, or anything in between. Tiny menu bar app.",
  openGraph: { title: "Gust", description: "Full blast. On demand. Fan control for Mac.", siteName: "Gust", type: "website" },
  twitter: { card: "summary_large_image", title: "Gust", description: "Full blast. On demand. Fan control for Mac." },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f4f5f7" },
    { media: "(prefers-color-scheme: dark)", color: "#08090b" },
  ],
};

// Runs before paint so the saved/system theme applies without a flash.
const themeScript = `try{var t=localStorage.theme;var d=t==="dark"||(t!=="light"&&matchMedia("(prefers-color-scheme: dark)").matches);document.documentElement.classList.toggle("dark",d)}catch(e){}`;

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${interTight.variable} h-full antialiased`} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body className="h-full font-sans">{children}</body>
    </html>
  );
}
