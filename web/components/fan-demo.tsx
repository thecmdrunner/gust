"use client";

import { useEffect, useRef, useState } from "react";

type Mode = "auto" | "min" | "max";
const MIN = 1350;
const MAX = 5777;
const modes: Mode[] = ["auto", "min", "max"];

export function FanBlades({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 100 100" className={className} aria-hidden>
      <defs>
        <linearGradient id="blade" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#5cc2ff" />
          <stop offset="1" stopColor="#1a4df2" />
        </linearGradient>
      </defs>
      {[0, 90, 180, 270].map((r) => (
        <path
          key={r}
          transform={`rotate(${r} 50 50)`}
          d="M50 42C47 32 44 18 53 9c9-8 25-2 24 11-1 11-12 17-20 22-3 2-5 1-7 0Z"
          fill="url(#blade)"
        />
      ))}
      <circle cx="50" cy="50" r="9" className="fill-bg" />
      <circle cx="50" cy="50" r="5" fill="url(#blade)" />
    </svg>
  );
}

export function FanDemo() {
  const [mode, setMode] = useState<Mode>("auto");
  const touched = useRef(false);
  const fanRef = useRef<HTMLDivElement>(null);
  const rpmRef = useRef<HTMLSpanElement>(null);
  const barRef = useRef<HTMLDivElement>(null);
  const glowRef = useRef<HTMLDivElement>(null);
  const modeRef = useRef<Mode>("auto");
  modeRef.current = mode;

  // Kick into Max shortly after load to show off the spin-up, unless the visitor already picked something.
  useEffect(() => {
    const t = setTimeout(() => !touched.current && setMode("max"), 1400);
    return () => clearTimeout(t);
  }, []);

  useEffect(() => {
    const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
    let rpm = MIN + 40;
    let angle = 0;
    let last = performance.now();
    let frame = 0;
    const tick = (now: number) => {
      const dt = Math.min((now - last) / 1000, 0.1);
      last = now;
      const m = modeRef.current;
      const target = m === "max" ? MAX : m === "min" ? MIN : MIN + 70 + Math.sin(now / 1800) * 60;
      rpm += (target - rpm) * (1 - Math.exp(-dt * 1.1));
      if (!reduce) angle = (angle + (dt * rpm * 360 * 0.05) / 60) % 360;
      const p = (rpm - MIN) / (MAX - MIN);
      if (fanRef.current) fanRef.current.style.transform = `rotate(${angle}deg)`;
      if (rpmRef.current) rpmRef.current.textContent = Math.round(rpm).toLocaleString("en-US");
      if (barRef.current) barRef.current.style.transform = `scaleX(${0.04 + p * 0.96})`;
      if (glowRef.current) glowRef.current.style.opacity = String(0.15 + p * 0.85);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, []);

  return (
    <div className="flex flex-col items-center">
      <div className="relative grid place-items-center">
        <div
          ref={glowRef}
          className="pointer-events-none absolute inset-[-18%] rounded-full bg-[radial-gradient(closest-side,rgb(56_140_255/0.35),transparent)] blur-2xl transition-opacity"
        />
        <div className="relative grid size-[min(40dvh,62vw)] place-items-center rounded-full border border-line bg-card shadow-[0_30px_80px_-30px_rgb(20_60_200/0.35)] [@media(max-height:740px)]:size-[min(30dvh,54vw)]">
          <div ref={fanRef} className="size-[82%] will-change-transform">
            <FanBlades className="size-full" />
          </div>
        </div>
      </div>

      <div className="mt-7 flex items-baseline gap-1.5 tabular-nums [@media(max-height:740px)]:mt-5">
        <span ref={rpmRef} className="text-5xl font-semibold tracking-tight sm:text-6xl">
          1,390
        </span>
        <span className="text-sm text-muted">rpm</span>
      </div>
      <div className="mt-3 h-1 w-40 overflow-hidden rounded-full bg-line">
        <div ref={barRef} className="h-full origin-left rounded-full bg-gradient-to-r from-[#5cc2ff] to-[#1a4df2]" />
      </div>

      <div role="radiogroup" aria-label="Fan mode" className="mt-7 flex rounded-full border border-line bg-card p-1 text-sm [@media(max-height:740px)]:mt-5">
        {modes.map((m) => (
          <button
            key={m}
            role="radio"
            aria-checked={mode === m}
            onClick={() => {
              touched.current = true;
              setMode(m);
            }}
            className={`rounded-full px-5 py-1.5 capitalize transition ${
              mode === m ? "bg-fg text-bg" : "text-muted hover:text-fg"
            }`}
          >
            {m}
          </button>
        ))}
      </div>
    </div>
  );
}
