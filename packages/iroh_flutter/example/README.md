# iroh_flutter example

A Flutter app that binds two iroh endpoints, connects them over QUIC, and echoes a message on a
bidirectional stream. The source is in [`lib/main.dart`](lib/main.dart).

```sh
cd packages/iroh_flutter/example
flutter run   # Android, iOS, macOS, Linux, or Windows
```

`integration_test/smoke_test.dart` checks the native library load, endpoint bind, the echo, and
address watching on a device:

```sh
flutter test integration_test
```
