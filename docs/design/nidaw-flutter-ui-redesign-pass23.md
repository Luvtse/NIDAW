# NIDAW Flutter UI / workflow pass 23

## Driver ride completion guards

Updated `apps/driver_app/lib/features/ride/presentation/bloc/active_ride_bloc.dart` to protect the completion transition from stale or duplicate requests:

- Ignore duplicate completion events while a completion request is in flight.
- Do not repeat completion for a ride already marked completed in the current BLoC state.
- Require the loaded ride ID to match the requested ride and require the ride to be in progress before invoking the completion use case.
- Reject non-finite or negative tip values before making a request.
- Verify the returned ride ID matches the requested ride before emitting completion.
- Reset the in-flight guard on both success and failure.

No endpoints, DTO fields, backend behavior, or tests were added. Flutter/Dart tooling is not installed in this environment, so analyzer, formatter, compilation, and device validation could not be run. Only source-level checks and ZIP integrity can be reported.
