// Plays the hero recording on a loop, with a Pause button. With reduced motion it stays on its poster frame
// until played, and the button starts it.
const video = document.querySelector("[data-video]");
const toggle = document.querySelector("[data-toggle]");

if (video && toggle) {
  const update = () => {
    toggle.textContent = video.paused ? "Play" : "Pause";
    toggle.setAttribute("aria-pressed", String(video.paused));
  };
  video.addEventListener("play", update);
  video.addEventListener("pause", update);
  toggle.addEventListener("click", () => (video.paused ? video.play() : video.pause()));
  toggle.hidden = false;

  if (!matchMedia("(prefers-reduced-motion: reduce)").matches) video.play().catch(() => {});
  update();
}
