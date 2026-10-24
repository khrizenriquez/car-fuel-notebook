# iOS CI parallel UI execution design

## Goal

Reduce the wall-clock duration of the `iPhone App Tests` GitHub Actions job by at
least 50%, from the successful baseline of 28 minutes 11 seconds to 14 minutes
or less. The change must retain every current app, integration, and UI assertion
on every pull request and `main` push.

## Evidence and root cause

The successful run for commit `258157e` spent 28 minutes 11 seconds in its
single `Run app, integration, and UI tests` step. Setup, checkout, simulator
inventory, and post-job work together took less than one minute.

The workflow explicitly disables test parallelism and limits Xcode to one
simulator destination. In addition, all 18 public UI scenarios live in
`CartrackSmokeUITests`, so XCTest has only one UI test class to schedule. The
same suite measured locally on iOS 26.5 at about 7 minutes 50 seconds; the
hosted macOS runner is slower, but its duration is dominated by serialized app
launches and independent end-to-end flows.

## Chosen approach

Keep a single GitHub Actions job and execute the existing UI coverage on up to
three simulator destinations concurrently. This avoids multiplying hosted-runner
jobs while using the capacity of the runner already allocated for the job.

Split `CartrackSmokeUITests` into three independent XCTestCase classes with no
shared mutable state:

1. **P0 and capture UI** — application creation/capture entry, locale and
   accessibility reachability, manual snapshot recovery, and the fundamental
   fill-up plus snapshot persistence path.
2. **Data and configuration UI** — vehicle configuration, multiple vehicles,
   edits/resets, adjustments, and snapshot-only state.
3. **Dashboard and presentation UI** — dashboard metrics and insight, reports
   exports, backup/map discovery, and README screenshot coverage.

Each test continues to call `launchApp` and creates or seeds its own data. No
test may rely on ordering or on data created by a test in another class. The
private Photos test remains separately gated and skipped by normal CI, exactly
as it is today.

## Execution model

The iOS CI job will have two phases after selecting and booting its simulator
environment:

1. Run `CartrackTests` serially, including the image-pipeline performance test.
   Its p95 and memory measurements must not contend with other test processes.
2. Run the three UI classes as three concurrent `xcodebuild` shards, each on a
   distinct compatible simulator: `CartrackCaptureUITests`,
   `CartrackDataUITests`, and `CartrackPresentationUITests`. This explicitly
   assigns each test exactly once; passing multiple destinations to one UI
   invocation would instead duplicate the full bundle on every destination.
   All shards preserve the existing test target and app-under-test
   configuration.

The implementation may use `build-for-testing` followed by
`test-without-building` if that is the most reliable way to avoid rebuilding
the app between phases. It must use the same derived-data/test artifacts for
both invocations and preserve `CODE_SIGNING_ALLOWED=NO`, the simulator-side
`CARTRACK_PERFORMANCE_P95_SECONDS=20`, and the existing cleanup trap.

## Quality and reliability requirements

- Every public test that ran before the change must run on every PR and push to
  `main`; no coverage is moved to a nightly-only workflow.
- A fresh app launch and deterministic seed/manual setup remain mandatory per
  UI test. Test names and accessibility assertions are retained.
- The performance test is isolated from concurrent UI work.
- The workflow must fail if either the app/integration phase or any UI shard
  fails. Test result output must identify the failing class and test name.
- Simulator destination count is capped at three to prevent unbounded resource
  use and keep the workflow within its 45-minute timeout.
- The existing private image matrix remains a local explicit command and is
  not uploaded or exposed to CI.

## Acceptance criteria

1. `Scripts/check_core_coverage.sh 90` still passes.
2. The complete public iOS suite passes locally on the iOS 26.5 simulator,
   including all 18 public UI tests and their intentional private-test skip.
3. A GitHub Actions run on `main` passes both `Core Coverage` and `iPhone App
   Tests`.
4. The remote iPhone App Tests job is at most 14 minutes, measured from the
   start to completion of that job. If hosted-runner variability prevents that
   result, the implementation records the measured split timings and retains
   the best stable configuration without reducing coverage.
5. The performance test remains below its simulator p95 limit and 160 MB
   memory ceiling.

## Rollback

If parallel UI execution introduces a deterministic isolation failure that
cannot be fixed by making the affected test self-contained, restore the prior
single-destination UI command while retaining the class boundaries and timing
instrumentation. Do not suppress, retry, or skip a failing test to meet the
duration target.
