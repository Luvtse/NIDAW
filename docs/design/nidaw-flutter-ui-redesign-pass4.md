# NIDAW Flutter UI redesign — Pass 4

Date: 2026-10-29

## Scope

This pass focuses on interaction-heavy Nidus trip surfaces rather than adding new routes or changing backend contracts.

## Updated surfaces

- Driver ride offer: branded dark arrival frame, clear countdown hierarchy, elevated fare-and-route panel, and softened action controls. Existing timer, accept, dismiss, and repository behavior are retained.
- Driver navigation: lavender route-planning canvas, clearer external-navigation affordances, and a more intentional bottom ride-control sheet. The page still clearly states that turn-by-turn directions open in the configured maps app; the visual canvas is not represented as a live map.
- Rider chat: branded participant header, warmer conversation canvas, differentiated sent/received bubbles, and improved message spacing. History, retries, real-time listening, and sending logic are unchanged.
- Rider safety toolkit: stronger safety-first header, calmer action cards, and clear locked-state iconography. Existing safety availability and emergency confirmation flows are unchanged.

## Constraints and validation

- No new endpoints, DTO fields, or product behavior were introduced.
- No tests were added, per the existing project instruction.
- Flutter/Dart SDKs are not available in this environment, so `flutter analyze` and device builds could not be run. Source was reviewed after edits and the deliverable archive integrity was checked; this is not a substitute for compilation or visual QA on devices.
