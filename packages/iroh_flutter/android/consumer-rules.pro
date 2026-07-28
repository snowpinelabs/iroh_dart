# rustls-platform-verifier (iroh's TLS certificate verification) resolves these Kotlin classes
# via JNI FindClass at runtime; R8 sees no Java-side references, so without keeps they would be
# stripped from release builds and every HTTPS verification would fail.
-keep class org.rustls.platformverifier.** { *; }
