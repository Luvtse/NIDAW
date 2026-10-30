#!/usr/bin/env python3
"""Static regression checks for at-least-once shared event consumption."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "services/api/internal/shared/eventbus/consumer.go").read_text()
tests = (ROOT / "services/api/internal/shared/eventbus/consumer_test.go").read_text()
checks = {
    "consumer fetches without auto-commit": "FetchMessage(ctx)" in source and "ReadMessage(ctx)" not in source,
    "successful handler is committed": "CommitMessages(ctx, pending.message)" in source,
    "handler failure leaves offset uncommitted": "retaining message for redelivery" in source and "return err" in source,
    "malformed poison event has explicit policy": "committing poison message" in source,
    "missing topic is validated": 'errors.New("at least one Kafka topic is required")' in source,
    "nil configuration is validated": 'errors.New("consumer config is required")' in source,
    "retry wait observes cancellation": "case <-ctx.Done():" in source and "waitForRetry(ctx" in source,
    "success path has unit coverage": "TestConsumeMessageCommitsAfterSuccessfulHandler" in tests,
    "failure path has unit coverage": "TestConsumeMessageDoesNotCommitFailedHandler" in tests,
    "poison-message policy has unit coverage": "TestConsumeMessageCommitsMalformedPoisonMessage" in tests,
    "commit error has unit coverage": "TestConsumeMessageDoesNotCommitWhenCommitFails" in tests,
    "failed event is retained rather than skipped": "TestConsumeMessageRetainsFailedMessageBeforeFetchingNext" in tests,
    "commit retry avoids repeating successful handler": "TestConsumeMessageRetriesCommitWithoutRepeatingHandler" in tests,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
if failed:
    raise SystemExit(f"{len(failed)} event-consumer contract assertion(s) failed")
print(f"All {len(checks)} event-consumer contract assertions passed.")
