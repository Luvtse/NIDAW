# NIDAW Flutter UI Redesign — Pass 21

## Scope
Consumer Vorax menu and checkout. This pass hardens the existing cart against menu changes between browsing and checkout without changing backend contracts or adding endpoints.

## Changes
- Retains the last successfully loaded menu snapshot for comparison during checkout.
- After fetching the authoritative menu, checkout stops if any selected item became unavailable and refreshes the displayed menu for review.
- Checkout stops if selected items now have blank or inconsistent currencies.
- Checkout stops when a selected item's price or currency differs from the last displayed menu, refreshes the menu, and asks the customer to review the updated menu before placing the order.
- Existing quantity payload and order creation call remain unchanged.

## Validation
- Reviewed the edited checkout branch and confirmed the existing `createOrder` call and quantities payload are preserved.
- Flutter/Dart SDK is not available in this environment; `flutter analyze`, formatting, compilation, and device testing could not be run.
