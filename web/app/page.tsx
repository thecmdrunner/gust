import Image from "next/image";
import { FanDemo } from "@/components/fan-demo";
import { ThemeToggle } from "@/components/theme-toggle";

export default function Home() {
  return (
    <div className="mx-auto flex h-dvh max-w-5xl flex-col px-6">
      <header className="flex items-center justify-between py-5">
        <div className="flex items-center gap-2.5">
          <Image src="/gust-icon.png" alt="" width={30} height={30} priority />
          <span className="text-lg font-semibold tracking-tight">Gust</span>
        </div>
        <ThemeToggle />
      </header>

      <main className="flex flex-1 flex-col items-center justify-center gap-8">
        <h1 className="text-center text-3xl font-semibold tracking-tight text-balance sm:text-4xl">
          Full blast. <span className="text-muted">On demand.</span>
        </h1>
        <FanDemo />
      </main>

      <footer className="flex flex-col items-center gap-2.5 pb-8">
        <a
          href="/Gust.zip"
          download
          className="flex items-center gap-2 rounded-full bg-fg px-6 py-3 text-sm font-medium text-bg transition hover:opacity-85 active:scale-[0.98]"
        >
          <svg viewBox="0 0 24 24" className="size-4" fill="currentColor" aria-hidden>
            <path d="M16.4 12.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9-1.7 0-3.3 1-4.2 2.6-1.8 3.1-.5 7.7 1.3 10.2.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8 1.6 0 2 .8 3.4.8 1.4 0 2.3-1.3 3.1-2.5 1-1.4 1.4-2.8 1.4-2.9 0 0-2.7-1-2.7-4.1zM13.9 5c.7-.8 1.2-2 1-3.2-1 0-2.3.7-3 1.5-.7.8-1.2 2-1.1 3.1 1.2.1 2.3-.6 3.1-1.4z" />
          </svg>
          Download for Mac
        </a>
        <p className="text-xs text-muted">Free · macOS 14+ · Apple Silicon</p>
      </footer>
    </div>
  );
}
