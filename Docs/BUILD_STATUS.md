# Build Smoke Test Status

| Date | Swift build | Swift warnings-as-errors | Swift tests | TipTap tests | Overall |
|------|-------------|--------------------------|-------------|--------------|---------|
| 2026-04-24 | ✅ Pass, with Convex linker deployment-target warnings (`libconvexmobile.a` built for macOS 26.2 while linking 26.0) | ✅ Pass after fixing `CiderDragPayload.swift` actor-isolation diagnostics; Convex linker warnings remain | ✅ Pass: XCTest suite and Swift Testing 291/291 | ✅ Pass: 10/10 | ✅ Core automated gate green; drag-out/manual filename retest passed |
| 2026-03-26 | ⏭ Skipped (swift not available in sandbox) | ⏭ Not run | ⏭ Not run | ❌ Vite build failed due missing `@rollup/rollup-linux-arm64-gnu` platform package; TypeScript passed | ⚠️ Partial |
| 2026-03-24 | ⏭ Skipped (swift not available in sandbox) | ⏭ Not run | ⏭ Not run | ❌ Vite build failed due missing `@rollup/rollup-linux-arm64-gnu` platform package; TypeScript passed | ⚠️ Partial |
| 2026-03-23 | ⏭ Skipped (swift not available in sandbox) | ⏭ Not run | ⏭ Not run | ❌ Vite build failed due missing `@rollup/rollup-linux-arm64-gnu` platform package; TypeScript passed | ⚠️ Partial |
| 2026-03-22 | ⏭ Skipped (swift not available in sandbox) | ⏭ Not run | ⏭ Not run | ❌ Vite build failed due missing `@rollup/rollup-linux-arm64-gnu` platform package; TypeScript passed | ⚠️ Partial |
| 2026-03-21 | ⏭ Skipped (swift not available in sandbox) | ⏭ Not run | ⏭ Not run | ❌ Vite build failed due missing `@rollup/rollup-linux-arm64-gnu` platform package; TypeScript passed | ⚠️ Partial |
| 2026-03-20 | ⏭ Skipped (swift not available in sandbox) | ⏭ Not run | ⏭ Not run | ❌ Vite build failed due missing `@rollup/rollup-linux-arm64-gnu` platform package; TypeScript passed | ⚠️ Partial |
