//! Android JNI bootstrap - installs the app's `JavaVM` + `Context` into the native layer.
//!
//! iroh needs a JNI handle on the Android app before the first `Endpoint` exists:
//!
//! * `iroh-dns` reads the system DNS servers through `ndk-context`. Uninitialized, that JNI
//!   lookup panics - and this crate ships release builds with `panic = "abort"`, so
//!   `Endpoint.bind` aborts the whole app with `android context was not initialized`
//!   (issue #8). Debug builds catch the panic and fall back to public DNS, which is why the
//!   crash only appears in `flutter build apk --release`.
//! * `netdev` (interface enumeration for iroh's netwatch) probes `ndk-context` with
//!   `catch_unwind`, which is equally fatal under `panic = "abort"`.
//! * `reqwest` (iroh's pkarr HTTPS publisher) verifies TLS certificates through
//!   `rustls-platform-verifier`, which needs the same context plus its Kotlin support classes
//!   (bundled by the plugin's Gradle build).
//!
//! The `IrohFlutterPlugin` Java class calls [`initAndroidContext`] from `onAttachedToEngine` -
//! the Android embedding registers plugins while the engine starts, before any Dart code can
//! reach the FFI surface. Initialization is process-wide and idempotent; engine re-attaches
//! (hot restart, add-to-app, extra engines) are no-ops.
//!
//! [`initAndroidContext`]: Java_io_snowpine_iroh_1flutter_IrohFlutterPlugin_initAndroidContext

use jni::errors::ThrowRuntimeExAndDefault;
use jni::objects::{JClass, JObject};
use jni::EnvUnowned;

/// `IrohFlutterPlugin.initAndroidContext(Context)` - publishes the process `JavaVM` and the
/// application `Context` to `ndk-context` (via [`iroh_dns::install_android_jni_context`]) and
/// initializes `rustls-platform-verifier`. Errors surface as a Java `RuntimeException` so a
/// broken bootstrap fails loudly at startup instead of aborting later inside iroh.
#[no_mangle]
pub extern "system" fn Java_io_snowpine_iroh_1flutter_IrohFlutterPlugin_initAndroidContext<
    'local,
>(
    mut env: EnvUnowned<'local>,
    _class: JClass<'local>,
    context: JObject<'local>,
) {
    env.with_env(|env| -> jni::errors::Result<()> {
        let vm = env.get_java_vm()?;
        let global_context = env.new_global_ref(&context)?;

        // Idempotent (OnceCell inside); takes its own global refs to the context + class loader.
        rustls_platform_verifier::android::init_with_env(env, context)?;

        // ndk-context asserts on double-initialization, so guard with Once. Both raw pointers
        // must stay valid for the life of the process: the JavaVM already is, and `into_raw`
        // deliberately leaks the context's global ref.
        static NDK_CONTEXT_INIT: std::sync::Once = std::sync::Once::new();
        NDK_CONTEXT_INIT.call_once(|| unsafe {
            iroh_dns::install_android_jni_context(
                vm.get_raw().cast(),
                global_context.into_raw().cast(),
            );
        });
        Ok(())
    })
    .resolve::<ThrowRuntimeExAndDefault>()
}
