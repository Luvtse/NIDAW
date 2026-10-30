# NIDAW Flutter UI redesign — Pass 11

Scope remains limited to the Nidus consumer app, Vorax consumer app, and driver app.

## Driver availability and location lifecycle

- Driver dashboard refreshes retain the loaded dashboard rather than replacing it with a full-screen spinner.
- Non-fatal refresh, availability, and location tracking failures are surfaced through the dashboard snackbar while preserving the last known dashboard state.
- Re-entering location tracking cancels the prior location subscription before attaching a new listener.
- Location updates emit against the latest bloc state after asynchronous uploads, avoiding overwriting newer availability or ride-offer state with a stale snapshot.
- The dashboard listener displays non-fatal messages from the loaded state.

## Vorax checkout and tracking

- Checkout validates the delivery address and refuses blank or extremely short entries.
- Checkout refreshes the menu before submitting and blocks submission if selected dishes are no longer available.
- Submitted quantities are filtered to positive quantities for currently known cart items.
- Order tracking now awaits the exact refresh request, prevents overlapping polling, and stops polling when the order reaches a terminal state, including delivered.

## Validation

- ZIP integrity check passed.
- Flutter/Dart SDK is not available in this environment; analyzer, formatting, builds, and device QA have not been run.
