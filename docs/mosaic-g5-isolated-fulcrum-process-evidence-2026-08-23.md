# Mosaic G5 Isolated Fulcrum-Process Evidence — 2026-08-23

## Status

This evidence closes the G5 isolated Fulcrum-process integration sub-gate for the concrete OpalBase chain adapter. It does not close Mosaic G5 or G6, authorize a canary, or change the public-disabled status. The locked application runtime remains on OpalBase `fcc930b4f7ab00dca6c9030c3ef3eb010bf1fb2a`; the test-only harness is checkpointed separately at `ab05b8eebdfb86728bae2c89c771cfc568339ec2` so Wallet does not need a new production pin.

## Exact graph

- OpalBase runtime: `fcc930b4f7ab00dca6c9030c3ef3eb010bf1fb2a`
- OpalBase isolated-process test harness: `ab05b8eebdfb86728bae2c89c771cfc568339ec2`
- OpalFusion: `79ba5f91449b2c0d5cd6ec73c38fafd58cae0b46`
- OpalCrypto: `23425db04075a48405d65cf6a3e2254911e626eb`
- SwiftFulcrum: `24b44bb2458822d14121dfbd57321fda7ae539ea`
- OpalDiagnostics: `7cd2e383309821e01903077c1e534174f9c8a964`

The verification lane used `Package.resolved` as the revision authority and task-local mirrors of the four owned dependency repositories. The first shared-cache attempt stopped before compilation because its cached OpalFusion repository lacked the exact `79ba5f9` object; switching to the owned local mirrors resolved all four exact revisions without changing the graph.

## Proven boundary

- The parent test launches a distinct `xctest` worker process. The worker hosts a repository-owned Network.framework WebSocket fixture bound only to `127.0.0.1`; it neither selects nor contacts an external endpoint.
- The production `MosaicPrivateAlphaRuntime.makeAttestedChainClient(configuration:)` path creates the exact-endpoint OpalBase Fulcrum client, negotiates through SwiftFulcrum, reads `server.features`, and accepts the fixture only when its freshly observed mainnet genesis hash equals the configured mainnet binding.
- The fixture rejects any broadcast whose raw bytes differ from the exact locally completed Mosaic transaction and returns only its expected transaction identifier.
- The concrete chain adapter observed the exact transaction through authoritative absence, exact broadcast, unconfirmed mempool presence, six-confirmation block presence, confirmed-to-mempool reorganization, and post-reorganization authoritative absence.
- The worker records the actual JSON-RPC method path. The passing run observed one `server.version`, two `server.features`, one `blockchain.transaction.broadcast`, and five exact verbose `blockchain.transaction.get` requests; the server rejected any unexpected method, identifier, verbosity flag, or transaction bytes.
- The existing fast session-owner test remained alongside the process integration and continued to prove guarded approval preview, durable dispatch intent before broadcast, at-most-one dispatch, exact confirmed reconciliation, explicit finality authorization, and cleanup authorization.

## Validation evidence

- Exact-resolved build and test discovery completed successfully after the local-mirror cache correction.
- `OPALBASE_RUN_MOSAIC_FULCRUM_PROCESS_INTEGRATION=1 swift test --filter 'AccountMosaicPrivateAlphaSessionOwnerChainValidator/exerciseIsolatedFulcrumProcess'` passed 1/1 in 0.963 seconds after a 7.10-second cached rebuild; the process test itself passed in 0.962 seconds on its final run.
- The combined focused slice passed 2/2 in 3.116 seconds with `--skip-build`: the isolated process test passed in 1.255 seconds and the session-owner chain test passed in 3.115 seconds.
- The worker has a five-second endpoint-publication deadline and a 60-second absolute lifetime, both below the roadmap's five-minute isolated-process cap.
- `git diff --check` passed before the harness checkpoint.

## Complexity and dependency decision

The fixture is opt-in test support rather than a production target, executable product, package dependency, or public API. It reuses the test bundle as the worker executable, Foundation for atomic state exchange, Network.framework for the localhost WebSocket boundary, and the production OpalBase and SwiftFulcrum stack under test. This keeps the dependency graph first-party, avoids a second Fulcrum abstraction, and leaves the locked runtime revision unchanged.

## Non-claims and remaining holds

No live Fulcrum server, Tor route, external network, mainnet broadcast, wallet value, canary, credential, paid service, or public Mosaic path was used or enabled. The synthetic worker proves concrete transport and fail-closed chain-state handling, not live-chain availability or safe value movement. G5 remains held because the exact-graph Wallet real-cryptography rehearsal timed out before the new chain boundary, and canary execution still requires separate external/value approval. G6 also remains held by inherited G4 review, signed runtime-drill, and environmental evidence gaps until the authoritative serial decision reconciles them.
