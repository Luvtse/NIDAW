# NIDAW Flutter UI Redesign — Pass 5

## Scope

This pass continues from the consumer/driver redesign archive and prioritizes unfinished interaction states over cosmetic-only changes.

### Driver earnings overview

- Removed the duplicate `padding` argument that prevented the page from compiling.
- Limited the period selector to the periods supported by the existing bloc: daily and weekly. Monthly was removed because there is no monthly event/use case in the current code.
- Connected period selection to the existing daily and weekly load events.
- Added a retryable error state and a no-activity chart state.
- Reworked the layout into a branded earnings summary, activity chart, compact stat cards, and detail action.

### Driver documents

- Improved the document and application-status cards using the existing theme palette.
- Made onboarding status more scannable and highlighted the server-provided status, missing documents, and review note.
- Preserved existing upload, replace, preview, refresh, and appeal actions.

## Validation limitations

Flutter and Dart SDKs are not installed in this environment. No analyzer, app build, device run, or screenshot validation was possible. The archive should be analyzed and built locally before release. No backend endpoints, DTO fields, or tests were added.
