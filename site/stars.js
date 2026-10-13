// Shows the repository's star count next to each "Star on GitHub" link. One unauthenticated request to GitHub's API,
// remembered for the tab's session so reloads don't eat into its rate limit (60 an hour per IP). If the request
// fails, or the count is still small, the links stay as plain text.

const REPO = "Stoupe/speak";
// Below this a count reads as "nobody cares" rather than "popular". Lower it, or set it to 0, to always show.
const MIN_STARS = 10;
const CACHE_KEY = `stars:${REPO}`;
const CACHE_MS = 60 * 60 * 1000;

async function fetchStars() {
  try {
    const cached = JSON.parse(sessionStorage.getItem(CACHE_KEY));
    if (cached && Date.now() - cached.at < CACHE_MS) return cached.count;
  } catch {}

  const response = await fetch(`https://api.github.com/repos/${REPO}`, {
    headers: { Accept: "application/vnd.github+json" },
  });
  if (!response.ok) throw new Error(`GitHub answered ${response.status}`);
  const { stargazers_count: count } = await response.json();
  if (!Number.isInteger(count)) throw new Error("No star count in the response");

  try {
    sessionStorage.setItem(CACHE_KEY, JSON.stringify({ count, at: Date.now() }));
  } catch {}
  return count;
}

function format(count) {
  if (count < 1000) return String(count);
  return `${(count / 1000).toFixed(count < 10000 ? 1 : 0).replace(/\.0$/, "")}k`;
}

const labels = document.querySelectorAll("[data-stars]");
if (labels.length) {
  fetchStars()
    .then((count) => {
      if (count < MIN_STARS) return;
      for (const label of labels) {
        // The label already holds the star icon; the count goes after it.
        label.append(format(count));
        const unit = document.createElement("span");
        unit.className = "visually-hidden";
        unit.textContent = count === 1 ? " star" : " stars";
        label.append(unit);
        label.hidden = false;
      }
    })
    .catch(() => {});
}
