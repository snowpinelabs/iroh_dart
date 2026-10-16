# rustls-platform-verifier checks TLS certificates for iroh. At run time, it finds these Kotlin
# classes through JNI FindClass. R8 sees no references to them from Java code. Without these keep
# rules, R8 removes the classes from release builds, and all HTTPS certificate checks fail.
-keep class org.rustls.platformverifier.** { *; }
