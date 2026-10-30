# NIDAW Flutter UI Redesign — Pass 20

## Scope

Consumer Vorax menu and cart consistency. No backend contract, endpoint, or DTO changes.

## Changes

- Prevents adding menu items priced in a different currency to an existing cart, avoiding a misleading subtotal that would label a mixed-currency sum with only the first item's currency.
- Rejects items with a blank currency instead of allowing an ambiguous subtotal.
- Uses one cart-add handler for both the initial add action and quantity increment, and clears a stale inline error after a valid add.

## Validation

- Inspected the menu item entity and existing cart/checkout flow; changes use the existing `MenuItem.currency` field only.
- Flutter/Dart SDK is not available in this environment, so analyzer, formatter, build, and device checks could not be run.
