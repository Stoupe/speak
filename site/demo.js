// Plays one dictation on the demo desktop, on a loop, the way the app does it: hold fn and the pill listens,
// words stream into the card (the first sentence is cleaned up while you're still talking), let go and the
// rest is cleaned up, the card folds back, the text is pasted into the chat and sent.
// Without JavaScript, or with reduced motion, the page shows the finished conversation instead.

const PIECES = [
  { raw: "yeah definitely um I'm free all Saturday", polished: "Yeah, definitely. I'm free all Saturday." },
  {
    raw: "so let's leave around nine no wait ten I need coffee first",
    polished: "Let's leave around ten, I need coffee first.",
  },
];
const BAR_COUNT = 24;

const demo = document.querySelector("[data-demo]");

if (demo && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
  play(demo);
}

function play(demo) {
  const $ = (name) => demo.querySelector(`[data-${name}]`);
  const pill = $("pill");
  const card = $("card");
  const live = $("live");
  const bars = $("bars");
  const messages = $("messages");
  const input = $("input");
  const placeholder = $("placeholder");
  const toggle = $("toggle");

  // The finished conversation is in the HTML for visitors without the animation; start without it.
  const sentTemplate = $("sent");
  sentTemplate.remove();

  // Runs only while on screen and not paused by the visitor.
  let onScreen = true;
  let pausedByVisitor = false;
  let resume = null;
  const running = () => onScreen && !pausedByVisitor;
  const update = () => {
    if (running() && resume) {
      resume();
      resume = null;
    }
  };

  new IntersectionObserver(([entry]) => {
    onScreen = entry.isIntersecting;
    update();
  }).observe(demo);

  toggle.hidden = false;
  toggle.addEventListener("click", () => {
    pausedByVisitor = !pausedByVisitor;
    toggle.setAttribute("aria-pressed", String(pausedByVisitor));
    toggle.textContent = pausedByVisitor ? "Play" : "Pause";
    update();
  });

  // Waits `ms` of running time.
  async function wait(ms) {
    for (let left = ms; left > 0; left -= 50) {
      if (!running()) await new Promise((resolve) => (resume = resolve));
      await new Promise((resolve) => setTimeout(resolve, Math.min(left, 50)));
    }
  }

  // Waveform: 24 bars of recent microphone level, newest on the right, like the app.
  const levels = new Array(BAR_COUNT).fill(0);
  const barEls = levels.map((_, i) => {
    const bar = document.createElement("i");
    bar.style.setProperty("--i", i);
    bars.append(bar);
    return bar;
  });
  let listening = false;
  let speaking = false;
  setInterval(() => {
    if (!running() || !listening) return;
    const level = speaking ? 0.2 + Math.random() * 0.8 * (0.5 + 0.5 * Math.sin(Date.now() / 90)) : Math.random() * 0.06;
    levels.shift();
    levels.push(level);
    barEls.forEach((bar, i) => bar.style.setProperty("--level", levels[i].toFixed(3)));
  }, 60);

  // The card's text: cleaned-up text, raw text waiting for cleanup, and the last couple of words, which the
  // recognizer may still change.
  let polished = "";
  let raw = [];

  function render({ freshPolish = false } = {}) {
    const parts = [];
    if (polished) {
      const span = document.createElement("span");
      span.className = freshPolish ? "polished is-new" : "polished";
      span.textContent = polished;
      parts.push(span);
    }
    const settled = raw.slice(0, -2);
    const changing = raw.slice(-2);
    if (settled.length) {
      const span = document.createElement("span");
      span.className = "pending";
      span.textContent = (parts.length ? " " : "") + settled.join(" ");
      parts.push(span);
    }
    if (changing.length) {
      const span = document.createElement("span");
      span.className = "volatile";
      span.append((parts.length ? " " : "") + changing.slice(0, -1).map((w) => w + " ").join(""));
      const newest = document.createElement("span");
      newest.className = "word";
      newest.textContent = changing.at(-1);
      span.append(newest);
      parts.push(span);
    }
    live.replaceChildren(...parts);
    if (pill.classList.contains("is-open")) card.style.height = `${live.offsetHeight}px`;
  }

  async function say(words) {
    speaking = true;
    for (const word of words) {
      raw.push(word);
      render();
      await wait(140 + Math.random() * 120);
    }
    speaking = false;
  }

  async function loop() {
    for (;;) {
      polished = "";
      raw = [];
      live.replaceChildren();
      input.textContent = "";
      placeholder.hidden = false;
      await wait(1200);

      // fn held: the pill appears and listens.
      pill.classList.add("is-shown");
      listening = true;
      await wait(500);

      // The first words open the card.
      const [first, second] = PIECES;
      const firstWords = first.raw.split(" ");
      raw.push(firstWords[0]);
      pill.classList.add("is-open");
      render();
      setTimeout(() => pill.classList.add("is-growing"), 650);
      await wait(200);
      await say(firstWords.slice(1));
      await wait(250);

      // The first sentence is cleaned up while the second is still being spoken.
      const secondWords = second.raw.split(" ");
      await say(secondWords.slice(0, 3));
      polished = first.polished;
      raw = raw.slice(firstWords.length);
      render({ freshPolish: true });
      await say(secondWords.slice(3));
      await wait(450);

      // fn released: the rest is cleaned up.
      listening = false;
      pill.classList.add("is-processing");
      await wait(900);
      polished = `${first.polished} ${second.polished}`;
      raw = [];
      render({ freshPolish: true });
      await wait(1300);

      // The card folds back into the pill as the text is pasted.
      pill.classList.remove("is-open", "is-growing");
      card.style.height = "0px";
      await wait(380);
      pill.classList.remove("is-shown", "is-processing");
      levels.fill(0);
      barEls.forEach((bar) => bar.style.setProperty("--level", 0));
      placeholder.hidden = true;
      input.textContent = `${polished} `;
      input.classList.add("is-new");
      await wait(60);
      input.classList.remove("is-new");
      await wait(1300);

      // Return: the message is sent.
      const sent = sentTemplate.cloneNode(true);
      sent.classList.add("is-arriving");
      messages.append(sent);
      input.textContent = "";
      placeholder.hidden = false;
      await wait(4200);

      sent.classList.add("is-leaving");
      await wait(450);
      sent.remove();
    }
  }

  loop();
}
