package com.nidaw.app;

import android.content.Context;
import androidx.multidex.MultiDex;
import io.flutter.app.FlutterApplication;

/**
 * NIDAW consumer application class.
 *
 * Phase 6 (Android startup optimization) contract:
 *   - This class performs NO synchronous network, disk or dependency-graph
 *     work. The only operation here is MultiDex installation, which is
 *     mandatory because build.gradle sets multiDexEnabled=true with
 *     minSdkVersion 23 (sub-API-21 legacy support).
 *   - All heavy initialization (Firebase, Hive, geocoding cache, FCM,
 *     WebSocket) happens after the first Flutter frame, in
 *     lib/core/startup/app_startup_coordinator.dart — never on this path.
 *   - If minSdk is ever raised to 21+, MultiDex can be dropped and this
 *     class replaced by io.flutter.app.FlutterApplication directly.
 */
public class NidawConsumerApplication extends FlutterApplication {
    @Override
    protected void attachBaseContext(Context base) {
        super.attachBaseContext(base);
        MultiDex.install(this);
    }
}
