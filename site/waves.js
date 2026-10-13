// Fills the two waveforms beside the headline. Each bar gets its own numbers; style.css does the moving.
// "said" bars twitch at their own pace, like a voice. "clean" bars rise and fall in one even wave. They come in
// one after the other; style.css staggers each bar's entrance by its position.
// Bars are tallest next to the text and shrink away from it. A fixed seed keeps the shape the same on every visit.

const WAVE_BARS = 40;

let seed = 7;
function random() {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

for (const wave of document.querySelectorAll("[data-wave]")) {
  const said = wave.dataset.wave === "said";
  wave.style.setProperty("--bars", WAVE_BARS);
  for (let i = 0; i < WAVE_BARS; i++) {
    // i counts away from the headline on both sides.
    const near = 1 - i / WAVE_BARS;
    const bar = document.createElement("i");
    bar.style.setProperty("--i", i);
    if (said) {
      const high = near * (0.35 + 0.65 * random());
      bar.style.setProperty("--low", (high * (0.1 + 0.3 * random())).toFixed(3));
      bar.style.setProperty("--high", high.toFixed(3));
      bar.style.setProperty("--duration", `${(0.5 + 0.9 * random()).toFixed(2)}s`);
      bar.style.setProperty("--delay", `${(-2 * random()).toFixed(2)}s`);
    } else {
      bar.style.setProperty("--high", (0.25 + 0.75 * near).toFixed(3));
    }
    // The left wave is laid out right to left, so bar 0 sits against the text there too.
    said ? wave.prepend(bar) : wave.append(bar);
  }
}
