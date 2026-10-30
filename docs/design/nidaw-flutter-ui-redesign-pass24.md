# NIDAW Flutter UI Redesign — Pass 24

## Scope
Driver document submission workflow only. No backend routes, DTO fields, or API contracts were added.

## Changes
- Document upload now lets the driver take a photo with the camera or choose an existing image from the gallery.
- Added short capture guidance to reduce blurry or cropped submissions.
- Keeps the existing image size/quality constraints, repository upload path, refresh behavior, and failure feedback.
- Dismissing the source chooser or image picker safely cancels without starting an upload.

## Validation
- Source-level checks only; Flutter/Dart SDK was not available for analysis, formatting, compilation, or device testing.
