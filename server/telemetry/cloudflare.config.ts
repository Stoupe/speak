import { bindings, defineConfig } from "cf/config";
import * as entrypoint from "./src/index.ts" with { type: "cf-worker" };

export default defineConfig({
	worker: {
		name: "speak-telemetry",
		compatibilityDate: "2026-11-04",
		entrypoint,
		// The only public address. No workers.dev URL and no per-version preview URLs.
		domains: ["speak-telemetry.stoupe.dev"],
		workersDev: false,
		previewUrls: false,
		// No request logs or traces: nothing about who sent a report is kept anywhere.
		observability: { enabled: false },
		env: {
			DB: bindings.d1({ name: "speak-telemetry", id: "8113e4ab-d7f9-4164-b537-239207213d89" }),
		},
	},
});
