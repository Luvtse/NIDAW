# Product event topic contract review — 2026-10-24

## Finding

`KafkaBus.Publish(ctx, topic, event)` writes to the exact `topic` argument. It does not rewrite messages to `nidaw.events`. Some consumer comments and `MemoryBus` behavior had claimed otherwise. That mismatch hid production routing defects in tests: a consumer subscribed to `nidaw.events` could appear to receive events published to `nidus.locations` because the in-memory bus ignored topics.

## Topic subscriptions corrected in this checkpoint

| Consumer | Subscribed topics | Reason |
|---|---|---|
| Notifications | `nidaw.events`, `nidus.rides`, `nidus.locations`, `payments` | Current producers publish ride lifecycle events, location-derived events, and payment events on these topics. |
| Telephony | `nidaw.events`, `nidus.rides` | Proxy sessions are provisioned/terminated from ride lifecycle events, including events emitted on `nidus.rides`. |
| Nidus WebSocket bridge | `nidaw.events`, `nidus.rides`, `nidus.locations`, `payments` | Live fan-out must observe actual producer topics rather than rely on a fictional canonical topic. |
| Driver-arriving watcher | `nidaw.events`, `nidus.locations` | Location updates may be published to `nidus.locations`; the legacy shared topic remains supported. |

Reliable consumers use stable, topic-qualified group IDs, so separate topics are consumed independently without consumers competing for the same event stream. The WebSocket bridge remains best-effort because it serves ephemeral live updates.

## In-memory contract

`MemoryBus` now routes only to subscribers of the exact published topic, rejects empty topics, and therefore more closely matches Kafka. Tests that previously relied on cross-topic broadcast must be corrected to publish on the topic under test. This is intentional: test doubles must not mask routing errors.

## Guarantees and limitations

- The code now explicitly subscribes to the producer topics listed above.
- Reliable topic subscription is at-least-once; handlers still need idempotency.
- The multi-topic helper validates the full topic list before registering subscriptions, but an underlying broker error during registration can still leave earlier topic subscriptions running until context cancellation.
- This is a source-level routing correction, not proof of a deployed Kafka topology. Broker-backed tests must verify topic existence, ACLs, restart/redelivery, partition rebalancing, and consumer-group behavior.
- The list is an observed inventory of current producers/consumers, not a complete schema registry. Corpus/Haven/Vorax/Logix outbox payload compatibility and schema evolution remain separate acceptance gates.
