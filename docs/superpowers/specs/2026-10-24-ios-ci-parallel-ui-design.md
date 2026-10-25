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

Run each UI shard in its own GitHub Actions job and allocate only one simulator
to each runner. This uses independent runner capacity, avoids CoreSimulator
startup/migration contention, and keeps the selected simulator alive for the
entire `xcodebuild` invocation.

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

The workflow has four independent macOS jobs followed by an aggregation check:

1. Run `CartrackTests` serially in the app/integration job, including the image-pipeline performance test.
   Its p95 and memory measurements must not contend with other test processes.
2. Run `CartrackCaptureUITests`, `CartrackDataUITests`, and
   `CartrackPresentationUITests` as a three-entry job matrix. Each entry boots
   exactly one compatible simulator and builds/tests its shard with
   `CODE_SIGNING_ALLOWED=NO`.
3. A short `iPhone App Tests` aggregation job succeeds only when the app job
   and every matrix entry succeed. It preserves the established required-check
   name while reporting failures from every shard.

This explicitly assigns each test once. It must not boot multiple freshly
created simulators on the same runner or use background `xcodebuild` processes
that compete for that runner's CoreSimulator service.

## Quality and reliability requirements

- Every public test that ran before the change must run on every PR and push to
  `main`; no coverage is moved to a nightly-only workflow.
- A fresh app launch and deterministic seed/manual setup remain mandatory per
  UI test. Test names and accessibility assertions are retained.
- The performance test is isolated from concurrent UI work.
- The workflow must fail if either the app/integration job or any UI shard
  fails. Test result output must identify the failing class and test name.
- Each macOS job uses one simulator and a 25-minute timeout. The matrix is
  fixed at three entries, preventing unbounded resource use.
- The existing private image matrix remains a local explicit command and is
  not uploaded or exposed to CI.

## Acceptance criteria

1. `Scripts/check_core_coverage.sh 90` still passes.
2. The complete public iOS suite passes locally on the iOS 26.5 simulator,
   including all 18 public UI tests and their intentional private-test skip.
3. A GitHub Actions run on `main` passes both `Core Coverage` and `iPhone App
   Tests`.
4. The remote CI wall-clock time from the first iOS job starting until the
   `iPhone App Tests` aggregation check completes is at most 14 minutes when
   GitHub Actions provides concurrent macOS capacity. If runner queueing or
   hosted-runner variability prevents that result, the implementation records
   the measured split timings and retains the reliable matrix without reducing
   coverage.
5. The performance test remains below its simulator p95 limit and 160 MB
   memory ceiling.

## Rollback

If parallel UI execution introduces a deterministic isolation failure that
cannot be fixed by making the affected test self-contained, restore the prior
single-destination UI command while retaining the class boundaries and timing
instrumentation. Do not suppress, retry, or skip a failing test to meet the
duration target.
