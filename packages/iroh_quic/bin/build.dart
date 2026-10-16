// `dart run iroh_quic:build` compiles the native library from source with cargo. Then it installs
// the native library into the cache that `iroh_quic:setup` uses, where `Iroh.init()` finds it.
// Use this tool if you do not want the prebuilt library. For example: you have no network, you
// want to audit the code, or no prebuilt library exists for your target.
//
//   dart run iroh_quic:build              # cargo build --release for the host, then install
//   dart run iroh_quic:build --debug      # faster build, no optimization
//   dart run iroh_quic:build --manifest-path path/to/rust/Cargo.toml
//
// This tool needs a Rust toolchain (https://rustup.rs). The pub.dev package contains the crate,
// so this tool also works from the pub cache.

import 'dart:io';
import 'dart:isolate';

import 'package:iroh_quic/src/ffi/prebuilt.dart';

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    _printUsage();
    return;
  }
  final release = !args.contains('--debug');
  final manifestPath = _optionValue(args, '--manifest-path') ?? await _defaultManifestPath();

  final target = currentPrebuiltTarget();
  if (target == null) {
    stderr.writeln(
      'iroh_quic: unknown platform/arch (${Platform.operatingSystem}); '
      'build manually with `cargo build` in the rust/ crate and pass libraryPath: to Iroh.init().',
    );
    exitCode = 1;
    return;
  }

  if (!File(manifestPath).existsSync()) {
    stderr.writeln('iroh_quic: crate manifest not found at $manifestPath');
    stderr.writeln(
      'Pass --manifest-path <path-to-rust/Cargo.toml> pointing at the iroh_quic crate.',
    );
    exitCode = 1;
    return;
  }

  if (!await _hasCargo()) {
    stderr.writeln(
      'iroh_quic: `cargo` not found. Install the Rust toolchain from https://rustup.rs, '
      'or run `dart run iroh_quic:setup` to download a signed prebuilt instead.',
    );
    exitCode = 1;
    return;
  }

  final profile = release ? 'release' : 'debug';
  stdout.writeln(
    'iroh_quic: building $profile from $manifestPath (this compiles the iroh stack)...',
  );
  final cargoArgs = <String>['build', if (release) '--release', '--manifest-path', manifestPath];
  final proc = await Process.start('cargo', cargoArgs, mode: ProcessStartMode.inheritStdio);
  final code = await proc.exitCode;
  if (code != 0) {
    stderr.writeln('iroh_quic: cargo build failed (exit $code).');
    exitCode = code;
    return;
  }

  // cargo writes <crate>/target/<profile>/<libFileName>. Copy it to the path that the loader reads.
  final crateDir = File(manifestPath).parent.path;
  final built = File('$crateDir/target/$profile/${target.libFileName}');
  if (!built.existsSync()) {
    stderr.writeln('iroh_quic: build succeeded but ${built.path} is missing.');
    exitCode = 1;
    return;
  }

  Directory(prebuiltCacheDir(target)).createSync(recursive: true);
  final dest = prebuiltCacheLibPath(target);
  built.copySync(dest);
  final mib = (built.lengthSync() / 1048576).toStringAsFixed(2);
  stdout.writeln('iroh_quic: installed ${target.libFileName} ($mib MiB) ->\n  $dest');
  stdout.writeln('iroh_quic: done. Iroh.init() will load it automatically.');
}

String? _optionValue(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  return null;
}

/// Returns the path of the crate manifest, `<iroh_quic package root>/rust/Cargo.toml`. This
/// function finds the package root from the package URI. This works from source and from the pub
/// cache. Do not use `Platform.script`: under `dart run`, it gives the pub snapshot directory.
Future<String> _defaultManifestPath() async {
  final libUri = await Isolate.resolvePackageUri(Uri.parse('package:iroh_quic/iroh_quic.dart'));
  if (libUri == null) {
    throw StateError('cannot resolve package:iroh_quic. Pass --manifest-path explicitly.');
  }
  // libUri is <pkg>/lib/iroh_quic.dart. The crate is in <pkg>/rust.
  final pkgRoot = File.fromUri(libUri).parent.parent.path;
  return '$pkgRoot/rust/Cargo.toml';
}

Future<bool> _hasCargo() async {
  try {
    final r = await Process.run('cargo', ['--version']);
    return r.exitCode == 0;
  } on Object {
    return false;
  }
}

void _printUsage() {
  stdout.writeln('''
iroh_quic:build - compile the native library from source and install it for Iroh.init().

Usage:
  dart run iroh_quic:build [--debug] [--manifest-path <rust/Cargo.toml>]

  --debug                 Unoptimized build (faster to compile).
  --manifest-path <path>  Cargo.toml of the iroh_quic crate (default: <package root>/rust/Cargo.toml).
  -h, --help              Show this help.

Requires a Rust toolchain (https://rustup.rs). Prefer no toolchain? Use `dart run iroh_quic:setup`
to download a signed prebuilt library instead.''');
}
