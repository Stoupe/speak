// Receives Speak's anonymous daily usage reports and stores them in D1.
//
// What is stored is exactly the validated report plus the UTC date it arrived. The request's IP address, headers
// and time of day are never read or stored, and this Worker has logging turned off (cloudflare.config.ts).
// Reports older than 13 months are deleted whenever a new one arrives (a cron trigger would need a workers.dev
// subdomain on the account).
import { env } from "cloudflare:workers";
import { MAX_BODY, parseReport, utcDay } from "./report.ts";

const ABOUT = `Speak's anonymous usage stats endpoint.
What is sent, why, and how to turn it off: https://github.com/Stoupe/speak#usage-stats
`;

export default {
	async fetch(request, _env, ctx) {
		const url = new URL(request.url);
		if (url.pathname === "/" && request.method === "GET") {
			return new Response(ABOUT, { headers: { "content-type": "text/plain; charset=utf-8" } });
		}
		if (url.pathname !== "/v1/report") return new Response("Not found\n", { status: 404 });
		if (request.method !== "POST") return new Response("Method not allowed\n", { status: 405, headers: { allow: "POST" } });
		if (!request.headers.get("content-type")?.startsWith("application/json")) {
			return new Response("Expected JSON\n", { status: 415 });
		}

		const text = await request.text();
		if (text.length > MAX_BODY) return new Response("Too large\n", { status: 413 });
		let body: unknown;
		try {
			body = JSON.parse(text);
		} catch {
			return new Response("Invalid JSON\n", { status: 400 });
		}
		const report = parseReport(body);
		if (typeof report === "string") return new Response(`Rejected: ${report}\n`, { status: 400 });

		await env.DB.prepare(
			`INSERT INTO reports (received, day, app, build, os, chip, locale, trigger, polish, intelligence,
				dictations, words, hold, hands_free, empty, cancelled)
			 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		)
			.bind(
				utcDay(new Date()), report.day, report.app, report.build, report.os, report.chip, report.locale,
				report.trigger, report.polish ? 1 : 0, report.intelligence ? 1 : 0, report.dictations, report.words,
				report.hold, report.handsFree, report.empty, report.cancelled,
			)
			.run();
		ctx.waitUntil(env.DB.prepare("DELETE FROM reports WHERE day < date('now', '-13 months')").run());
		return new Response(null, { status: 204 });
	},
} satisfies ExportedHandler<Env>;
