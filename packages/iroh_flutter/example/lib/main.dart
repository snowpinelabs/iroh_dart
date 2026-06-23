import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:iroh_flutter/iroh_flutter.dart';

/// Example/verification harness for iroh_flutter. On a real device it
/// proves the native library loads (ABI handshake), the async runtime drives iroh, and two
/// in-process endpoints complete a byte-identical echo over a direct loopback connection.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IrohExampleApp());
}

class IrohExampleApp extends StatelessWidget {
  const IrohExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'iroh_flutter example',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const _HomePage(),
  );
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  String _status = 'Tap "Initialize" to load the native library.';
  String _abi = '-';
  String _irohVersion = '-';
  String _caps = '-';
  bool _busy = false;

  Future<void> _init() async {
    setState(() => _busy = true);
    try {
      await Iroh.init();
      setState(() {
        _abi = 'v${Iroh.abiVersion}';
        _irohVersion = Iroh.irohVersion;
        _caps = Iroh.capabilities.toString();
        _status = 'Native library loaded. ABI handshake OK.';
      });
    } on IrohException catch (e) {
      setState(() => _status = 'Init failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  /// Binds two endpoints and runs a byte-identical echo over a direct loopback connection.
  Future<void> _runEcho() async {
    setState(() {
      _busy = true;
      _status = 'Running echo...';
    });
    const alpn = 'iroh-dart/example/echo/0';
    Endpoint? server;
    Endpoint? client;
    try {
      await Iroh.init();
      server = await Endpoint.bind(alpns: [alpn.codeUnits], relayMode: RelayMode.disabled);
      client = await Endpoint.bind(relayMode: RelayMode.disabled);

      final serverAddr = EndpointAddr(server.id, ipAddrs: _loopback(server.boundSockets));
      final payload = Uint8List.fromList('hello from iroh_flutter'.codeUnits);

      final served = () async {
        final conn = await server!.accept();
        final (send, recv) = await conn!.acceptBi();
        final data = await recv.readToEnd(1 << 16);
        await send.writeAll(data);
        await send.finish();
      }();

      final conn = await client.connect(serverAddr, alpn.codeUnits);
      final (send, recv) = await conn.openBi();
      await send.writeAll(payload);
      await send.finish();
      final echoed = await recv.readToEnd(1 << 16);
      await served;

      final ok = _listEquals(echoed, payload);
      setState(
        () => _status = ok
            ? 'Echo OK - ${echoed.length} bytes byte-identical.\n'
                  'remote id: ${conn.remoteId.fmtShort()}'
            : 'Echo MISMATCH!',
      );
    } on IrohException catch (e) {
      setState(() => _status = 'Echo failed: $e');
    } finally {
      await client?.close();
      await server?.close();
      setState(() => _busy = false);
    }
  }

  static List<String> _loopback(List<String> bound) {
    final out = <String>[];
    for (final b in bound) {
      final i = b.lastIndexOf(':');
      if (i < 0) continue;
      final port = b.substring(i + 1);
      final host = b.substring(0, i);
      out.add(host.startsWith('[') || host.contains(':') ? '[::1]:$port' : '127.0.0.1:$port');
    }
    return out;
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('iroh_flutter example')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _InfoRow(label: 'ABI', value: _abi),
          _InfoRow(label: 'iroh core', value: _irohVersion),
          _InfoRow(label: 'Capabilities', value: _caps),
          const SizedBox(height: 16),
          Card(
            child: Padding(padding: const EdgeInsets.all(16), child: Text(_status)),
          ),
          const Spacer(),
          FilledButton(onPressed: _busy ? null : _init, child: const Text('Initialize')),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _busy ? null : _runEcho,
            child: const Text('Run echo demo'),
          ),
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: <Widget>[
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
