# Trusted-Time Rollback Fix

Date: 2026-07-12 EDT

Outcome: **FIXED**

## Finding and security invariant

The cached signed pack-status envelope was protected by a trusted-time floor,
but the same-boot uptime-derived floor existed only in memory. The Keychain
record was rewritten only after accepting a new signed status. A process restart
or reboot followed by a device wall-clock rollback could therefore reload the
older verification time and extend authorization of a status that had already
expired during the prior boot.

The invariant is: before cached status can authorize a scan, the highest trusted
wall-clock floor observed by the client must be validated and persisted in
ThisDeviceOnly Keychain state. A later client or boot may keep or advance that
floor, but may never lower it. Invalid protected state and a failed Keychain
write must fail closed.

Legitimate behavior that must remain intact:

- wall-clock movement forward advances the floor;
- system uptime advances the floor during one boot;
- a significant wall-clock rollback fails closed across a relaunch;
- any persisted status loaded by a new app process requires a successful
  signed HTTPS refresh before cached authorization;
- a changed boot estimate cannot be bypassed by holding wall time at or just
  above the persisted floor, even if the new uptime exceeds the old anchor;
- a successful trusted refresh establishes the new uptime anchor without ever
  lowering the prior floor;
- an offline scan remains authorized on the same boot while the signed status
  is still inside its validity window;
- a newer, valid signed status can move the expiry window forward.

## Fix

`PackStatusTrustedTime` is a small Codable state machine in AICCore. It validates
finite, nonnegative time values and rejects any decoded state whose floor is
below the wall clock represented by its own anchor. Advancement takes the
maximum of the persisted floor, observed wall clock, and same-boot monotonic
uptime floor, then reanchors without decreasing the result. Uptime is accepted
as monotonic evidence only when both its ordering and the wall-clock-derived
boot estimate match the stored anchor. A changed boot estimate is never allowed
to authorize cached status offline, regardless of whether wall time is behind,
equal to, or slightly ahead of the durable floor. This remains true even when a
later boot's uptime has grown beyond the earlier boot's small uptime anchor.

`PackStatusClient` treats every status loaded from protected storage by a new
app process as requiring a network refresh. That refresh must include a valid
HTTP `Date`, pass the existing signed-envelope checks, and be persisted before
authorization. Refresh persistence takes the maximum of the prior floor and
the newly trusted time, so a stale or rolled-back local clock cannot lower it.
A client-level regression loads an otherwise valid persisted envelope into a
new `PackStatusClient`, forces the network request to fail, calls authorization
with `refresh: false`, and confirms the client still makes exactly one request
and fails with `statusUnavailable` rather than falling back to the cache.

`PackStatusClient.authorize` now advances and saves this state before it checks
or acts on cached pack status. The existing Keychain item remains scoped to
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Decode, invariant, or save
failures map to `statusUnavailable`, so scanning stops rather than using
untrusted time. The three legacy persisted JSON key names remain unchanged so
existing pre-release Keychain records migrate without deletion.

## Regression evidence

The new reboot regression was run against an implementation that mirrored the
old non-persisting behavior. It failed as expected:

```text
testTrustedTimeFloorSurvivesNewClientAfterRebootAndClockRollback
XCTAssertThrowsError failed: did not throw an error
Executed 1 test, with 1 failure
```

With the fix, tests serialize the advanced state (modeling Keychain), decode it
into a new client, and cover multiple rollback cases. A significant wall-clock
rollback across a relaunch throws `invalidState`. A changed boot with reset or
later-greater uptime also throws when the wall clock is held at the floor plus
one second. A trusted refresh reanchors the new boot while preserving the
maximum prior floor.

Additional tests confirm forward time, a forward-clock trusted refresh, and
ordinary same-boot offline authorization inside the signed window still work. Malformed or
internally rolled-back state cannot decode.

## Verification

All commands were run without a simulator.

```sh
cd ios && swift test --filter PackStatusTests
```

Result: 16 tests passed, 0 failed.

```sh
cd ios && swift test
```

Result: 48 tests passed, 0 failed.

```sh
xcodebuild -project ios/AIC.xcodeproj -scheme AIC -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/aic-trusted-time-derived \
  CODE_SIGNING_ALLOWED=NO build
```

Result: `** BUILD SUCCEEDED **`. This compiled the real iOS `AIC` target,
including `PackStatusClient`, without signing or launching a simulator.

The final app-hosted simulator suite, including the new process-restart
regression, passed 68 tests with zero failures.

## Residual limitation

iOS does not expose a repository-native trusted clock that measures time while
the app is not running or the device is powered off. The fix therefore requires
one successful signed HTTPS status refresh whenever a new app process loads
persisted status; offline scans remain available only after that refresh for the
life of the process and while the signed window remains valid. The server
`Date` can advance but never lower the floor.
