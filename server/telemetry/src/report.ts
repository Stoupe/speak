// The one report shape Speak sends (see Packages/SpeakKit/Sources/SpeakCore/UsageStats.swift and the README's
// "Usage stats" section). Anything else is rejected: unknown or missing fields, wrong types, values out of range.

export interface Report {
	v: 1;
	day: string;
	app: string;
	build: number;
	os: string;
	chip: string;
	locale: string;
	trigger: "fn" | "rightOption" | "rightCommand";
	polish: boolean;
	intelligence: boolean;
	dictations: number;
	words: number;
	hold: number;
	handsFree: number;
	empty: number;
	cancelled: number;
}

const FIELDS = [
	"v", "day", "app", "build", "os", "chip", "locale", "trigger", "polish", "intelligence",
	"dictations", "words", "hold", "handsFree", "empty", "cancelled",
] as const;

/** Largest accepted request body, in bytes. A real report is about 300. */
export const MAX_BODY = 2048;

const DAY_MS = 86_400_000;

const isCount = (value: unknown, max: number): value is number =>
	Number.isInteger(value) && (value as number) >= 0 && (value as number) <= max;

const isText = (value: unknown, pattern: RegExp): value is string =>
	typeof value === "string" && pattern.test(value);

/** Returns the report if `body` is exactly a valid one, else a short reason. `now` is injectable for tests. */
export function parseReport(body: unknown, now = new Date()): Report | string {
	if (typeof body !== "object" || body === null || Array.isArray(body)) return "not an object";
	const keys = Object.keys(body);
	if (keys.length !== FIELDS.length || !FIELDS.every((field) => keys.includes(field))) return "unexpected fields";
	const r = body as Record<string, unknown>;

	if (r.v !== 1) return "unknown version";
	if (!isText(r.day, /^\d{4}-\d{2}-\d{2}$/)) return "bad day";
	const day = Date.parse(`${r.day}T00:00:00Z`);
	// The Mac's local date: allow time zones ahead of UTC, and reports held back a week (laptop closed, offline).
	if (Number.isNaN(day) || day > now.getTime() + DAY_MS || day < now.getTime() - 8 * DAY_MS) return "day out of range";
	if (!isText(r.app, /^\d{1,3}(\.\d{1,3}){0,2}$/)) return "bad app";
	if (!isCount(r.build, 1_000_000)) return "bad build";
	if (!isText(r.os, /^\d{1,3}\.\d{1,3}$/)) return "bad os";
	if (!isText(r.chip, /^[A-Za-z0-9 ]{1,40}$/)) return "bad chip";
	if (!isText(r.locale, /^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,4})?$/)) return "bad locale";
	if (r.trigger !== "fn" && r.trigger !== "rightOption" && r.trigger !== "rightCommand") return "bad trigger";
	if (typeof r.polish !== "boolean" || typeof r.intelligence !== "boolean") return "bad flag";

	const counts = [r.dictations, r.hold, r.handsFree, r.empty, r.cancelled];
	if (!counts.every((count) => isCount(count, 5000))) return "bad count";
	if (!isCount(r.words, 500_000) || (r.words as number) % 10 !== 0) return "bad words";
	if ((r.hold as number) + (r.handsFree as number) !== r.dictations) return "counts don't add up";

	return r as unknown as Report;
}

/** UTC date as YYYY-MM-DD. */
export const utcDay = (date: Date) => date.toISOString().slice(0, 10);
