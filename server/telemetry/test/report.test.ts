import assert from "node:assert/strict";
import { test } from "node:test";
import { MAX_BODY, parseReport } from "../src/report.ts";

const now = new Date("2026-11-06T12:00:00Z");
const valid = {
	v: 1, day: "2026-11-05", app: "0.3", build: 40, os: "27.0", chip: "Apple M1", locale: "en-NZ",
	trigger: "fn", polish: true, intelligence: true,
	dictations: 14, words: 320, hold: 12, handsFree: 2, empty: 1, cancelled: 0,
};
const reject = (changes: Record<string, unknown>) => typeof parseReport({ ...valid, ...changes }, now) === "string";

test("accepts a valid report", () => {
	assert.deepEqual(parseReport(valid, now), valid);
	assert.ok(JSON.stringify(valid).length < MAX_BODY);
});

test("rejects extra or missing fields", () => {
	assert.ok(reject({ id: "abc" }));
	const { cancelled: _, ...missing } = valid;
	assert.equal(typeof parseReport(missing, now), "string");
	assert.equal(typeof parseReport([valid], now), "string");
	assert.equal(typeof parseReport(null, now), "string");
});

test("rejects wrong types and values", () => {
	assert.ok(reject({ v: 2 }));
	assert.ok(reject({ trigger: "space" }));
	assert.ok(reject({ polish: "yes" }));
	assert.ok(reject({ dictations: -1, hold: -1 }));
	assert.ok(reject({ dictations: 1.5 }));
	assert.ok(reject({ words: 321 }));
	assert.ok(reject({ hold: 13 }));
	assert.ok(reject({ chip: "<script>" }));
	assert.ok(reject({ locale: "en_NZ.UTF-8" }));
	assert.ok(reject({ app: "0.3; drop table" }));
});

test("only accepts recent days", () => {
	assert.ok(!reject({ day: "2026-11-07" })); // a time zone ahead of UTC
	assert.ok(!reject({ day: "2026-10-30" }));
	assert.ok(reject({ day: "2026-11-08" }));
	assert.ok(reject({ day: "2026-10-01" }));
	assert.ok(reject({ day: "2026-13-01" }));
});
