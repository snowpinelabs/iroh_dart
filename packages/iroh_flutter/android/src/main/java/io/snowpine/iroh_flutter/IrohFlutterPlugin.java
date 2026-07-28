package io.snowpine.iroh_flutter;

import android.content.Context;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Bootstraps the native iroh library with the Android application context.
 *
 * <p>iroh reads the system DNS servers, enumerates network interfaces, and verifies TLS
 * certificates through JNI, so the Rust side must hold the process {@code JavaVM} and an
 * application {@link Context} before the first {@code Endpoint} is bound. Without them a release
 * build aborts with {@code android context was not initialized} (issue #8).
 *
 * <p>The Android embedding instantiates this plugin while the engine starts - before any Dart
 * code can reach the FFI surface - so the context is always installed in time. Dart still opens
 * the library itself via {@code DynamicLibrary.open}; the {@link System#loadLibrary} here maps
 * the same shared object and lets the JVM resolve the native method below.
 */
public class IrohFlutterPlugin implements FlutterPlugin {
  private static boolean initialized = false;

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    synchronized (IrohFlutterPlugin.class) {
      if (initialized) {
        return;
      }
      System.loadLibrary("irohdart_ffi");
      initAndroidContext(binding.getApplicationContext());
      initialized = true;
    }
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {}

  private static native void initAndroidContext(Context context);
}
