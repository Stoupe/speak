// Header wordmark. It starts as the mark: the icon's waveform, three bars either side of the cursor. A second after
// load the right-hand bars travel off, unrolling the name behind them, and fade out like the end of a sentence.
// Hovering anywhere on the wordmark plays this backwards, back to the mark. The hover area is the whole link, which
// is as wide as the word whether or not it's showing, so collapsing never moves the edge out from under the pointer.
// data-expanded on .wordmark holds the state; set or remove it from anywhere and the wordmark animates to match.
// index.html holds more than one wordmark to compare names; only the one that isn't hidden is animated.

const SPLIT = 1100;
const FADE_START = 800;
const FADE = 380;
const FADE_STAGGER = 70;
const TOTAL = FADE_START + 2 * FADE_STAGGER + FADE;
// Where the leading bar comes to rest: this far past the end of the word.
const LEAD = 120;
// Collapsing runs the same timeline backwards, a bit quicker.
const COLLAPSE_SPEED = 1.6;

const wordmark = document.querySelector(".wordmark:not([hidden])");

if (wordmark) {
  // The word has to be in its real font (and weight) before it can be measured.
  const weight = getComputedStyle(wordmark.querySelector("text")).fontWeight;
  document.fonts.load(`${weight} 80px "Bricolage Grotesque"`).finally(() => setUp(wordmark));
}

function setUp(svg) {
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const text = svg.querySelector("text");
  const unroll = svg.querySelector(".wordmark-unroll");
  const wave = svg.querySelector(".wordmark-wave");

  // Everything in the SVG's own units. The clip grows from its x in the markup to just past the word's end; the
  // bars travel from where they sit in the mark (allowing for any translate on their group) to LEAD past it.
  const end = text.x.baseVal[0].value + text.getComputedTextLength();
  const unrollX = unroll.x.baseVal.value;
  const groupX = wave.parentNode.transform?.baseVal.consolidate()?.matrix.e ?? 0;
  const barX = wave.firstElementChild.x.baseVal.value + groupX;
  const travel = end + LEAD - barX;
  unroll.setAttribute("width", end + 80 - unrollX);

  // Every part ends at TOTAL, so reversing from the end starts them all together.
  const part = (node, keyframes, delay, duration, easing) =>
    node.animate(keyframes, { delay, duration, easing, endDelay: TOTAL - delay - duration, fill: "both" });
  const split = "cubic-bezier(0.65, 0, 0.35, 1)";
  const around = (x, scale) => `translate(${x}px, 0) ${scale} translate(${-x}px, 0)`;
  const timeline = [
    // The clip starts at or left of the leading bar and covers less ground, so the bars stay just ahead of the word.
    // Starts at a sliver rather than 0, so the clip is never an empty region (WebKit mishandles those).
    part(unroll, [{ transform: around(unrollX, "scaleX(0.001)") }, { transform: around(unrollX, "scaleX(1)") }], 0, SPLIT, split),
    part(wave, [{ transform: "translateX(0)" }, { transform: `translateX(${travel}px)` }], 0, SPLIT, split),
    ...[...wave.children].map((bar, i) =>
      part(bar, [{ opacity: 1, scale: "1 1" }, { opacity: 0, scale: "1 0.15" }], FADE_START + i * FADE_STAGGER, FADE, "ease-in"),
    ),
  ];
  for (const animation of timeline) animation.pause();

  const show = (expanded) => {
    for (const animation of timeline) {
      animation.playbackRate = expanded ? 1 : -COLLAPSE_SPEED;
      if (still) animation.currentTime = expanded ? TOTAL : 0;
      else animation.play();
    }
  };

  let expanded = false;
  new MutationObserver(() => {
    const now = svg.hasAttribute("data-expanded");
    if (now !== expanded) show((expanded = now));
  }).observe(svg, { attributes: true, attributeFilter: ["data-expanded"] });

  // Mouse only: on touch screens pointerenter/leave fire around every tap, which would fold and unfold it on the way
  // to following the link.
  const area = svg.closest("a") ?? svg;
  area.addEventListener("pointerenter", (event) => {
    if (event.pointerType === "mouse") svg.removeAttribute("data-expanded");
  });
  area.addEventListener("pointerleave", (event) => {
    if (event.pointerType === "mouse") svg.setAttribute("data-expanded", "");
  });

  // If the pointer is already resting on it, stay as the mark until it leaves.
  setTimeout(() => area.matches(":hover") || svg.setAttribute("data-expanded", ""), still ? 0 : 1000);
}
