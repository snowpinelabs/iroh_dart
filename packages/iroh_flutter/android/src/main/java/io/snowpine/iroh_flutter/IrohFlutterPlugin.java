package io.snowpine.iroh_flutter;

import android.content.Context;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Gives the JavaVM and the Android Context to the native library (the Android bootstrap).
 *
 * <p>iroh uses JNI to read the system DNS servers, list the network interfaces, and check TLS
 * certificates. Thus, the native library must have the {@code JavaVM} of the process and the
 * application {@link Context} before the first {@code Endpoint} binds. Without them, a release
 * build stops with the error {@code android context was not initialized}.
 *
 * <p>The Android embedding makes an instance of this plugin when the engine starts. This occurs
 * before Dart code can call the FFI, so the Android Context is always ready in time. Dart opens
 * the native library with {@code DynamicLibrary.open}. The {@link System#loadLibrary} call here
 * maps the same shared object and lets the JVM find the native method below.
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
