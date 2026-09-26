import Image from "next/image";
import { FanDemo } from "@/components/fan-demo";
import { ThemeToggle } from "@/components/theme-toggle";

const REPO = "https://github.com/thecmdrunner/gust";

function GitHubIcon({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      className={className}
      fill="currentColor"
      aria-hidden
    >
      <path d="M12 .5a11.5 11.5 0 0 0-3.64 22.41c.58.1.79-.25.79-.56v-2c-3.2.7-3.88-1.37-3.88-1.37-.52-1.33-1.28-1.69-1.28-1.69-1.05-.71.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.76 2.7 1.25 3.36.96.1-.75.4-1.25.73-1.54-2.56-.29-5.24-1.28-5.24-5.69 0-1.26.45-2.29 1.19-3.1-.12-.29-.52-1.46.11-3.05 0 0 .97-.31 3.17 1.18a11 11 0 0 1 5.77 0c2.2-1.49 3.17-1.18 3.17-1.18.63 1.59.23 2.76.11 3.05.74.81 1.19 1.84 1.19 3.1 0 4.42-2.69 5.39-5.25 5.68.41.36.78 1.06.78 2.14v3.17c0 .31.21.67.8.56A11.5 11.5 0 0 0 12 .5Z" />
    </svg>
  );
}

export default function Home() {
  return (
    <div className="mx-auto flex h-dvh max-w-5xl flex-col px-6">
      <header className="flex items-center justify-between py-5">
        <div className="flex items-center gap-2.5">
          <Image src="/gust-icon.png" alt="" width={30} height={30} priority />
          <span className="text-lg font-semibold tracking-tight">Gust</span>
        </div>
        <div className="flex items-center gap-1">
          <a
            href={REPO}
            aria-label="Source on GitHub"
            title="Source on GitHub"
            className="grid size-9 place-items-center rounded-full text-muted transition hover:bg-line hover:text-fg"
          >
            <GitHubIcon className="size-[18px]" />
          </a>
          <ThemeToggle />
        </div>
      </header>

      <main className="flex flex-1 flex-col items-center justify-center gap-8">
        <a
          href={REPO}
          className="-mb-3 flex items-center gap-2 rounded-full border border-line bg-card px-3.5 py-1 text-xs text-muted transition hover:text-fg"
        >
          <span className="size-1.5 rounded-full bg-emerald-500" />
          Free &amp; open source
          <span aria-hidden>→</span>
        </a>
        <h1 className="text-center text-3xl font-semibold tracking-tight text-balance sm:text-4xl">
          Full blast. <span className="text-muted">On demand.</span>
        </h1>
        <FanDemo />
      </main>

      <footer className="flex flex-col items-center gap-2.5 pb-8">
        <div className="flex items-center gap-2">
          <a
            href={`${REPO}/releases/latest/download/Gust.zip`}
            className="flex items-center gap-2 rounded-full bg-fg px-6 py-3 text-sm font-medium text-bg transition hover:opacity-85 active:scale-[0.98]"
          >
            <svg
              viewBox="0 0 24 24"
              className="size-4"
              fill="currentColor"
              aria-hidden
            >
              <path d="M16.4 12.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9-1.7 0-3.3 1-4.2 2.6-1.8 3.1-.5 7.7 1.3 10.2.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8 1.6 0 2 .8 3.4.8 1.4 0 2.3-1.3 3.1-2.5 1-1.4 1.4-2.8 1.4-2.9 0 0-2.7-1-2.7-4.1zM13.9 5c.7-.8 1.2-2 1-3.2-1 0-2.3.7-3 1.5-.7.8-1.2 2-1.1 3.1 1.2.1 2.3-.6 3.1-1.4z" />
            </svg>
            Download for Mac
          </a>
          <a
            href={REPO}
            className="flex items-center gap-2 rounded-full border border-line bg-card px-5 py-3 text-sm font-medium transition hover:bg-line active:scale-[0.98]"
          >
            <GitHubIcon className="size-4" />
            View source
          </a>
        </div>
        <p className="text-xs text-muted">
          MIT licensed · macOS 14+ · Apple Silicon
        </p>
      </footer>
    </div>
  );
}
