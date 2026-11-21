import type { ReactNode } from "react";

/** Theme objects drawn in the four corners of a themed pitch. They sit below the player layer,
    inside the outer touchline margin, so faces, names and slot buttons always stay on top. */
const SCENERY: Record<string, { top: ReactNode; bottom: ReactNode }> = {
  myth: {
    top: <>
      <path d="M6 10h28l-3 6H9Z" fill="#e9dcb4" stroke="#9c7f3d"/>
      <path d="M8 5h24v5H8Z" fill="#d8c48d" stroke="#9c7f3d"/>
      <path d="M11 16h18v60H11Z" fill="#f3ecd6" stroke="#a88b48"/>
      <path d="M15 18v56m5-56v56m5-56v56" stroke="#c7b07a"/>
      <path d="M7 76h26v4H7Z" fill="#d8c48d" stroke="#9c7f3d"/>
    </>,
    bottom: <>
      <path d="M5 66h30v8H5Z" fill="#d8c48d" stroke="#9c7f3d"/>
      <path d="M11 22h18v44H11Z" fill="#f3ecd6" stroke="#a88b48"/>
      <path d="M15 24v40m5-40v40m5-40v40" stroke="#c7b07a"/>
      <path d="M10 22 13 12h14l3 10Z" fill="#e9dcb4" stroke="#9c7f3d"/>
      <path d="M20 4c-6 4-8 8-6 8 3 0 4-4 6-8Zm0 0c6 4 8 8 6 8-3 0-4-4-6-8Z" fill="#d9b44a"/>
    </>,
  },
  engineering: {
    top: <>
      <g className="scenery-spin" style={{ transformOrigin: "18px 22px" }}>
        <circle cx="18" cy="22" r="11" fill="#123642" stroke="#6ff3e2" strokeWidth="1.5"/>
        <path d="M18 7v6m0 18v6M3 22h6m18 0h6M7.4 11.4l4.2 4.2m12.8 12.8 4.2 4.2m0-21.2-4.2 4.2M11.6 28.4l-4.2 4.2" stroke="#6ff3e2" strokeWidth="3"/>
        <circle cx="18" cy="22" r="4" fill="#6ff3e2"/>
      </g>
      <path d="M30 40h6v38h-6zM24 48h18" stroke="#3fb8b0" strokeWidth="2" fill="#0b2a33"/>
      <circle cx="33" cy="60" r="2" fill="#ffe36b"/>
    </>,
    bottom: <>
      <path d="M4 78V50h12l6-8h14v36Z" fill="#0f2f3a" stroke="#4fd8cc" strokeWidth="1.5"/>
      <path d="M8 56h8m-8 6h8m-8 6h8M24 50h8v20h-8Z" stroke="#4fd8cc"/>
      <circle cx="28" cy="56" r="1.8" className="scenery-blink" fill="#ffe36b"/>
      <circle cx="28" cy="63" r="1.8" fill="#6ff3e2"/>
    </>,
  },
  christmas: {
    top: <>
      <path d="M20 6 31 24h-5l9 15h-6l10 17H1l10-17H5l9-15H9Z" fill="#1d6b4c" stroke="#e9f5ec" strokeWidth="1.2" strokeLinejoin="round"/>
      <path d="M20 1l1.6 3.4L25 5l-3 2 1 4-3-2-3 2 1-4-3-2 3.4-.6Z" className="scenery-blink" fill="#ffd95a"/>
      <circle cx="16" cy="28" r="1.8" fill="#e9483f"/><circle cx="25" cy="38" r="1.8" fill="#ffd95a"/><circle cx="13" cy="48" r="1.8" fill="#ffd95a"/><circle cx="28" cy="51" r="1.8" fill="#e9483f"/>
      <path d="M17 56h6v8h-6Z" fill="#6b4226"/>
    </>,
    bottom: <>
      <path d="M2 72q18-10 36 0v8H2Z" fill="#f4f7f2"/>
      <path d="M6 54h16v16H6Z" fill="#c63c37" stroke="#fff" strokeWidth="1"/>
      <path d="M14 54v16M6 62h16" stroke="#ffd95a" strokeWidth="2"/>
      <path d="M24 60h12v11H24Z" fill="#2f7a59" stroke="#fff"/>
      <path d="M30 60v11" stroke="#fff" strokeWidth="2"/>
      <path d="M10 54q4-6 4 0 0-6 4 0" stroke="#ffd95a" strokeWidth="1.5"/>
    </>,
  },
  volcano: {
    top: <>
      <path d="M0 4h40L33 18l5 12-11 6 3 14-14-8-6 12L0 44Z" fill="#231b1d" stroke="#4a3330"/>
      <path d="M10 8l6 10-4 8 9 6m6-24-3 9 7 6" stroke="#ff7a35" strokeWidth="1.6" className="scenery-glow"/>
    </>,
    bottom: <>
      <path d="M2 80 8 52l8 6 6-22 8 14 5-6 4 36Z" fill="#2a2023" stroke="#4a3330"/>
      <path d="M22 36l-2 14 6 8-3 12m-11-18 2 12" stroke="#ff7a35" strokeWidth="1.6" className="scenery-glow"/>
      <circle cx="30" cy="28" r="1.6" fill="#ffb35a" className="scenery-ember"/>
      <circle cx="14" cy="40" r="1.3" fill="#ff7a35" className="scenery-ember"/>
    </>,
  },
  cosmos: {
    top: <>
      <circle cx="18" cy="22" r="11" fill="#7b5cc7"/>
      <path d="M11 14a11 11 0 0 1 15 2" stroke="#d9ccff" strokeWidth="2" strokeLinecap="round"/>
      <ellipse cx="18" cy="22" rx="19" ry="5" transform="rotate(-18 18 22)" stroke="#c9d6ff" strokeWidth="1.6"/>
      <path d="M33 46l1.2 2.8L37 50l-2.8 1.2L33 54l-1.2-2.8L29 50l2.8-1.2Z" className="scenery-blink" fill="#fff"/>
    </>,
    bottom: <>
      <path d="M24 46a14 14 0 1 0 8 25 11 11 0 1 1-8-25Z" fill="#e9e3ff"/>
      <path d="M8 60l1 2.4 2.4 1-2.4 1L8 67l-1-2.6-2.4-1L7 62.4Z" className="scenery-blink" fill="#b6f2ff"/>
      <path d="M4 30l16 9" stroke="#b6f2ff" strokeWidth="1.4" strokeLinecap="round" opacity=".6"/>
      <circle cx="21" cy="40" r="2" fill="#fff"/>
    </>,
  },
  sky: {
    top: <>
      <path d="M2 30q0-8 8-8 2-8 11-7 8-3 12 5 7 1 6 10Z" fill="#ffffff" opacity=".95"/>
      <path d="M6 44h28l-6 10H12Z" fill="#7a5a3a"/><path d="M6 44q14-6 28 0" fill="#5fbf5a"/>
      <path d="M14 54l2 10 3-10M24 54l1 6 2-6" stroke="#5a4028" strokeWidth="1.5"/>
    </>,
    bottom: <>
      <path d="M4 62h32l-8 14H12Z" fill="#7a5a3a"/><path d="M4 62q16-7 32 0" fill="#5fbf5a"/>
      <path d="M12 62V44m0 0-6 6m6-6 6 4" stroke="#6b4a2a" strokeWidth="2"/><circle cx="12" cy="40" r="7" fill="#3f9e48"/>
      <path d="M22 34q0-5 5-5 1-4 6-3 4 0 5 4" stroke="#fff" strokeWidth="3" strokeLinecap="round"/>
    </>,
  },
  arcade: {
    top: <>
      <path d="M8 6h24v48H8Z" fill="#1b0b33" stroke="#ff2fb3" strokeWidth="1.5"/>
      <path d="M12 10h16v14H12Z" fill="#2ff5ff" className="scenery-blink" opacity=".85"/>
      <circle cx="15" cy="34" r="3" fill="#ffe36b"/><circle cx="25" cy="34" r="2.5" fill="#ff2fb3"/>
      <path d="M8 54h24v6H8Z" fill="#ff2fb3"/>
    </>,
    bottom: <>
      <path d="M6 76V54h28v22" stroke="#2ff5ff" strokeWidth="1.5" fill="#160827"/>
      <path d="M10 60h6v6h-6zM20 60h6v6h-6z" fill="#ff2fb3" className="scenery-blink"/>
      <path d="M14 46h12v8H14Z" fill="#ffe36b"/><path d="M20 40v6" stroke="#ffe36b" strokeWidth="2"/>
    </>,
  },
  desert: {
    top: <>
      <path d="M20 66V30" stroke="#8a5a2b" strokeWidth="3"/>
      <path d="M20 30q-14-4-18 6 8-6 18-6Zm0 0q14-4 18 6-8-6-18-6Zm0 0q-10-10-16-6 8 0 16 6Zm0 0q10-10 16-6-8 0-16 6Z" fill="#3f9e48" stroke="#2a6e30" strokeWidth=".8"/>
      <circle cx="17" cy="33" r="2" fill="#7a4a1a"/><circle cx="23" cy="33" r="2" fill="#7a4a1a"/>
    </>,
    bottom: <>
      <path d="M0 78q14-14 40-6v8H0Z" fill="#e0b46a"/>
      <path d="M10 70V52m0 4h-5v-6m5 10h5v-8" stroke="#3f8a45" strokeWidth="4" strokeLinecap="round"/>
      <circle cx="30" cy="40" r="6" fill="#ffd34a" className="scenery-blink"/>
    </>,
  },
  deepsea: {
    top: <>
      <path d="M4 4q8 14 2 28 8-8 6 10 6-12 10-4" stroke="#3fd0c0" strokeWidth="2.5" strokeLinecap="round"/>
      <circle cx="28" cy="20" r="3" stroke="#bff6ff" className="scenery-ember"/><circle cx="32" cy="34" r="2" stroke="#bff6ff" className="scenery-ember"/>
      <path d="M22 46q6-6 12 0-6 6-12 0Zm12 0 5-4v8Z" fill="#ffb347"/>
    </>,
    bottom: <>
      <path d="M8 80V60m0 6-6-8m6 4 6-10m-6 18 7-6" stroke="#ff6b8b" strokeWidth="3" strokeLinecap="round"/>
      <path d="M26 80V64m0 4-5-6m5 0 4-8" stroke="#ffa24a" strokeWidth="3" strokeLinecap="round"/>
      <circle cx="20" cy="44" r="2.5" stroke="#bff6ff" className="scenery-ember"/><circle cx="30" cy="36" r="1.8" stroke="#bff6ff" className="scenery-ember"/>
    </>,
  },
  blossom: {
    top: <>
      <path d="M4 4q16 10 20 34" stroke="#6b3a2a" strokeWidth="2.5"/>
      {[[10,10],[20,16],[14,24],[26,28],[22,38]].map(([x,y]) => <circle key={`${x}${y}`} cx={x} cy={y} r="4.5" fill="#ffc3dc" stroke="#e05a96" strokeWidth=".6"/>)}
      <path d="M30 44v4" stroke="#6b3a2a"/><path d="M26 48h8v10h-8Z" fill="#e0344a" className="scenery-blink"/><path d="M26 52h8" stroke="#ffd76b"/>
    </>,
    bottom: <>
      <path d="M10 80V58h20v22" fill="#a33a2a"/><path d="M4 58h32l-4-6H8Z" fill="#3a2a24"/><path d="M4 52h32" stroke="#3a2a24" strokeWidth="2"/>
      <path d="M14 64h4v8h-4zM22 64h4v8h-4z" fill="#ffd76b" opacity=".85"/>
      <circle cx="30" cy="40" r="2" fill="#ffc3dc"/><circle cx="12" cy="44" r="1.6" fill="#ffc3dc"/>
    </>,
  },
  haunted: {
    top: <>
      <circle cx="24" cy="16" r="10" fill="#fff6c9" className="scenery-blink"/><circle cx="28" cy="13" r="9" fill="#1a1530"/>
      <path d="M6 40q4-4 8 0 4-4 8 0M8 52q3-3 6 0 3-3 6 0" stroke="#2a2440" strokeWidth="1.8"/>
    </>,
    bottom: <>
      <path d="M6 80V60q8-10 16 0v20Z" fill="#7d7a8c" stroke="#3a3848"/><path d="M14 64v8m-3-5h6" stroke="#3a3848" strokeWidth="1.5"/>
      <ellipse cx="30" cy="72" rx="8" ry="6.5" fill="#ff8a1f" stroke="#9a4a0a"/><path d="M30 65v-4" stroke="#3f7a2a" strokeWidth="2"/>
      <path d="M26 70l2-2 2 2m2-2 2 2m-7 4h8" stroke="#3a1a05" strokeWidth="1.2"/>
    </>,
  },
  candy: {
    top: <>
      <circle cx="18" cy="18" r="12" fill="#fff" stroke="#ff4f8b" strokeWidth="1.5"/>
      <path d="M18 6a12 12 0 0 1 0 24M8 12a12 12 0 0 1 20 12M6 20a12 12 0 0 1 14-14" stroke="#ff4f8b" strokeWidth="3"/>
      <path d="M18 30v34" stroke="#fff" strokeWidth="3"/><path d="M18 30v34" stroke="#c9c9c9" strokeWidth="1"/>
    </>,
    bottom: <>
      <path d="M6 80V54q0-8 8-8t8 8v26" fill="none" stroke="#fff" strokeWidth="5"/>
      <path d="M6 80V54q0-8 8-8t8 8v26" fill="none" stroke="#e0344a" strokeWidth="5" strokeDasharray="4 4"/>
      <path d="M26 64h10l-2 14h-6Z" fill="#7ad4ff"/><circle cx="31" cy="60" r="5" fill="#fff3fa" stroke="#ff9ac4"/>
    </>,
  },
  ruins: {
    top: <>
      <path d="M6 6h28v40H6Z" fill="#8c8a7a" stroke="#4a4a3a"/>
      <path d="M12 16h5v5h-5zM23 16h5v5h-5z" fill="#2f3a2a"/><path d="M14 30h12v4H14Z" fill="#2f3a2a"/>
      <circle cx="14.5" cy="18.5" r="1.5" fill="#7dff8b" className="scenery-blink"/><circle cx="25.5" cy="18.5" r="1.5" fill="#7dff8b" className="scenery-blink"/>
      <path d="M4 8q6 20 2 40m28-40q-4 16 2 34" stroke="#3f8a45" strokeWidth="2.2" strokeLinecap="round"/>
    </>,
    bottom: <>
      <path d="M4 80V62h12v-8h10v8h10v18Z" fill="#8c8a7a" stroke="#4a4a3a"/>
      <path d="M4 66h32M16 54v26m10-18v18" stroke="#6e6c5e"/>
      <path d="M6 62q10-8 14 2 6-10 14-2" stroke="#3f8a45" strokeWidth="2.4" strokeLinecap="round"/>
    </>,
  },
};

export function PitchScenery({ theme }: { theme: string }) {
  const art = SCENERY[theme];
  if (!art) return null;
  return (
    <span className={`pitch-scenery scenery-${theme}`} aria-hidden="true">
      {(["tl", "tr", "bl", "br"] as const).map(corner => (
        <svg key={corner} className={`scenery-${corner}`} viewBox="0 0 40 80" fill="none" focusable="false">
          {corner[0] === "t" ? art.top : art.bottom}
        </svg>
      ))}
    </span>
  );
}
