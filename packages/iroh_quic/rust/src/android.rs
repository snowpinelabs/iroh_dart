//! Android JNI bootstrap. This module gives the `JavaVM` and the `Context` of the app to the
//! native layer.
//!
//! iroh needs a JNI handle to the Android app before the first endpoint exists:
//!
//! * `iroh-dns` reads the system DNS servers through `ndk-context`. If `ndk-context` has no
//!   context, this JNI call panics. Release builds of this crate use `panic = "abort"`. Thus
//!   `Endpoint.bind` stops the full app with the message `android context was not initialized`.
//!   Debug builds catch the panic and use public DNS servers. Thus the crash occurs only in
//!   `flutter build apk --release`.
//! * `netdev` gets the network interfaces for the iroh `netwatch` crate. It reads `ndk-context`
//!   inside `catch_unwind`, which also stops the app under `panic = "abort"`.
//! * `reqwest` publishes the pkarr records of iroh over HTTPS. It verifies TLS certificates
//!   through `rustls-platform-verifier`. That verifier needs the same context and its Kotlin
//!   support classes. The Gradle build of the plugin bundles these classes.
//!
//! The `IrohFlutterPlugin` Java class of the `iroh_flutter` plugin calls [`initAndroidContext`]
//! from `onAttachedToEngine`. The Android embedding registers plugins when the engine starts,
//! before Dart code can call the FFI functions. The initialization applies to the full process,
//! and a second call has no effect. Thus a new attach of the engine does nothing. This occurs on
//! hot restart, in add-to-app, and with more engines.
//!
//! [`initAndroidContext`]: Java_io_snowpine_iroh_1flutter_IrohFlutterPlugin_initAndroidContext

use jni::errors::ThrowRuntimeExAndDefault;
use jni::objects::{JClass, JObject};
use jni::EnvUnowned;

/// Implements `IrohFlutterPlugin.initAndroidContext(Context)`.
///
/// Gives the process `JavaVM` and the application `Context` to `ndk-context` through
/// [`iroh_dns::install_android_jni_context`]. Also initializes `rustls-platform-verifier`.
/// If an error occurs, the function throws a Java `RuntimeException`. Thus a bad bootstrap fails
/// clearly at startup, and iroh does not stop the app later.
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

        // A second call has no effect because this function uses a `OnceCell`.
        // The function keeps its own global references to the context and the class loader.
        rustls_platform_verifier::android::init_with_env(env, context)?;

        // `ndk-context` asserts on a second initialization, so a `Once` guards the call.
        // Both raw pointers must stay valid until the process stops. The `JavaVM` pointer is
        // always valid. `into_raw` leaks the global reference to the context on purpose.
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
