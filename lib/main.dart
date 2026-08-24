import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const AppNavegadorTempoReal());
}

class AppNavegadorTempoReal extends StatelessWidget {
  const AppNavegadorTempoReal({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GPS Navegação Entregas',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const TelaGPSTempoReal(),
    );
  }
}

class TelaGPSTempoReal extends StatefulWidget {
  const TelaGPSTempoReal({super.key});

  @override
  State<TelaGPSTempoReal> createState() => _TelaGPSTempoRealState();
}

class _TelaGPSTempoRealState extends State<TelaGPSTempoReal> {
  final MapController _mapController = MapController();

  LatLng _posicaoVeiculo = const LatLng(-23.328000, -46.732000);
  StreamSubscription<Position>? _streamPosicao;
  double _anguloCarro = 0.0;

  bool _emNavegacao = false;
  bool _emParadaEntrega = false;
  bool _carregandoRota = false;

  List<LatLng> _pontosDaViaReal = [];
  String _distanciaTexto = 'Calculando...';
  String _tempoTexto = '-- min';

  final List<Map<String, dynamic>> _paradas = [
    {
      'endereco': 'Rod. Pres. Tancredo Neves - Caieiras / Perus',
      'latLng': const LatLng(-23.355000, -46.765000),
      'entregue': false,
    },
    {
      'endereco': 'Av. dos Coqueiros, 200 - Centro',
      'latLng': const LatLng(-23.320000, -46.720000),
      'entregue': false,
    },
  ];

  @override
  void initState() {
    super.initState();
    _iniciarMonitoramentoGPSReal();
    _buscarRotaRealPelasVias();
  }

  @override
  void dispose() {
    _streamPosicao?.cancel();
    super.dispose();
  }

  Future<void> _iniciarMonitoramentoGPSReal() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    try {
      final posInicial = await Geolocator.getCurrentPosition();
      setState(() {
        _posicaoVeiculo = LatLng(posInicial.latitude, posInicial.longitude);
      });
      _mapController.move(_posicaoVeiculo, 16.0);
    } catch (_) {}

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _streamPosicao = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position pos) {
      final novaPos = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _posicaoVeiculo = novaPos;
        if (pos.heading != 0) {
          _anguloCarro = pos.heading * (3.141592653589793 / 180.0);
        }
      });

      if (_emNavegacao) {
        _mapController.move(novaPos, 17.5);
      }
    });
  }

  Future<void> _buscarRotaRealPelasVias() async {
    final pendentes = _paradas.where((p) => !p['entregue']).toList();
    if (pendentes.isEmpty) {
      setState(() => _pontosDaViaReal = []);
      return;
    }

    setState(() => _carregandoRota = true);

    LatLng destino = pendentes.first['latLng'];
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${_posicaoVeiculo.longitude},${_posicaoVeiculo.latitude};'
      '${destino.longitude},${destino.latitude}'
      '?overview=full&geometries=geojson',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coordinates = data['routes'][0]['geometry']['coordinates'] as List;
        final double distMetros = data['routes'][0]['distance'].toDouble();
        final double duracaoSegundos = data['routes'][0]['duration'].toDouble();

        List<LatLng> rotaExtraida = coordinates.map((c) => LatLng(c[1], c[0])).toList();

        setState(() {
          _pontosDaViaReal = rotaExtraida;
          _distanciaTexto = '${(distMetros / 1000).toStringAsFixed(1)} km';
          _tempoTexto = '${(duracaoSegundos / 60).round()} min';
          _carregandoRota = false;
        });
      }
    } catch (_) {
      setState(() => _carregandoRota = false);
    }
  }

  void _abrirCameraScan() async {
    final status = await Permission.camera.request();
    if (!mounted) return;

    if (status.isGranted) {
      final resultado = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const TelaLeitorScanner()),
      );

      if (resultado != null && resultado.isNotEmpty) {
        _adicionarParadaEscaneada(resultado);
      }
    } else {
      _mostrarDialogoManual();
    }
  }

  void _mostrarDialogoManual() {
    final textEdit = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adicionar Pacote Manual'),
        content: TextField(
          controller: textEdit,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Código do pacote ou endereço',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (textEdit.text.trim().isNotEmpty) {
                Navigator.pop(ctx);
                _adicionarParadaEscaneada(textEdit.text.trim());
              }
            },
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
  }

  void _adicionarParadaEscaneada(String codigoLido) {
    setState(() {
      _paradas.add({
        'endereco': 'Entrega #$codigoLido',
        'latLng': LatLng(_posicaoVeiculo.latitude + 0.003, _posicaoVeiculo.longitude + 0.003),
        'entregue': false,
      });
    });
    _buscarRotaRealPelasVias();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pacote $codigoLido adicionado à rota!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _marcarComoEntregue(int index) {
    setState(() {
      _paradas[index]['entregue'] = !_paradas[index]['entregue'];
    });
    _buscarRotaRealPelasVias();
  }

  void _iniciarNavegacao() {
    setState(() {
      _emNavegacao = true;
      _emParadaEntrega = false;
    });
    _mapController.move(_posicaoVeiculo, 17.5);
  }

  void _continuarProximaEntrega() {
    final pendentes = _paradas.where((p) => !p['entregue']).toList();
    if (pendentes.isNotEmpty) {
      setState(() {
        pendentes.first['entregue'] = true;
        _emParadaEntrega = false;
      });
    }

    final novasPendentes = _paradas.where((p) => !p['entregue']).toList();
    if (novasPendentes.isEmpty) {
      setState(() => _emNavegacao = false);
      _mapController.move(_posicaoVeiculo, 14.0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todas as entregas concluídas!'), backgroundColor: Colors.green),
      );
    } else {
      _buscarRotaRealPelasVias();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Marker marcadorVeiculo = Marker(
      point: _posicaoVeiculo,
      width: 50,
      height: 50,
      child: Transform.rotate(
        angle: _anguloCarro,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: const Color(0xFF1A73E8),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(blurRadius: 6, color: Colors.black38, offset: Offset(0, 2))
                ],
              ),
              child: const Icon(Icons.navigation, color: Colors.white, size: 12),
            ),
          ],
        ),
      ),
    );

    final List<Marker> marcadoresParadas = _paradas.asMap().entries.map((entry) {
      int index = entry.key;
      var parada = entry.value;
      bool entregue = parada['entregue'] == true;

      return Marker(
        point: parada['latLng'] as LatLng,
        width: 38,
        height: 38,
        child: GestureDetector(
          onTap: () => _marcarComoEntregue(index),
          child: Container(
            decoration: BoxDecoration(
              color: entregue ? Colors.green.shade600 : const Color(0xFF1A73E8),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(blurRadius: 4, color: Colors.black38, offset: Offset(0, 2))
              ],
            ),
            child: Center(
              child: entregue
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
        ),
      );
    }).toList();

    final paradaAtual = _paradas.firstWhere(
      (p) => !p['entregue'],
      orElse: () => {'endereco': 'Sem entregas pendentes'},
    );

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _posicaoVeiculo,
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.exemplo.rotas',
              ),
              if (_pontosDaViaReal.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _pontosDaViaReal,
                      color: const Color(0xFF2C22E8),
                      strokeWidth: _emNavegacao ? 7.5 : 5.0,
                    ),
                  ],
                ),
              MarkerLayer(markers: [marcadorVeiculo, ...marcadoresParadas]),
            ],
          ),

          if (_emNavegacao) ...[
            Positioned(
              top: 35,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _emParadaEntrega ? Colors.orange.shade900 : const Color(0xFF00564D),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(blurRadius: 8, color: Colors.black45, offset: Offset(0, 3))
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _emParadaEntrega ? Colors.orange.shade800 : Colors.teal.shade800,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _emParadaEntrega ? Icons.local_shipping : Icons.turn_slight_right,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _emParadaEntrega ? 'Você Chegou!' : _distanciaTexto,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            paradaAtual['endereco'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(blurRadius: 10, color: Colors.black26, offset: Offset(0, -3))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, size: 28, color: Colors.black87),
                          onPressed: () {
                            setState(() {
                              _emNavegacao = false;
                              _emParadaEntrega = false;
                            });
                            _mapController.move(_posicaoVeiculo, 15.0);
                          },
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _emParadaEntrega ? 'No Local de Entrega' : _tempoTexto,
                                style: TextStyle(
                                  color: _emParadaEntrega ? Colors.orange.shade800 : const Color(0xFF1E8E3E),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _emParadaEntrega ? 'Entregue o pacote ao cliente' : '$_distanciaTexto restantes',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.my_location, size: 28, color: Color(0xFF1A73E8)),
                          onPressed: () => _mapController.move(_posicaoVeiculo, 17.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (!_emParadaEntrega)
                      ElevatedButton.icon(
                        onPressed: () => setState(() => _emParadaEntrega = true),
                        icon: const Icon(Icons.pause_circle_filled, color: Colors.white),
                        label: const Text(
                          'Parada para a Entrega',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 45),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: _continuarProximaEntrega,
                        icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                        label: const Text(
                          'Continuar para Próxima Entrega',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E8E3E),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 45),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],

          if (!_emNavegacao)
            Positioned(
              bottom: 15,
              left: 10,
              right: 10,
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _carregandoRota ? 'Calculando vias...' : 'Entregas (${_paradas.where((p) => !p['entregue']).length})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _abrirCameraScan,
                            icon: const Icon(Icons.camera_alt, size: 15),
                            label: const Text('Scan', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A73E8),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              minimumSize: const Size(0, 34),
                            ),
                          ),
                          const SizedBox(width: 6),
                          ElevatedButton.icon(
                            onPressed: _paradas.any((p) => !p['entregue']) ? _iniciarNavegacao : null,
                            icon: const Icon(Icons.navigation, size: 15),
                            label: const Text('Iniciar', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E8E3E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              minimumSize: const Size(0, 34),
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      SizedBox(
                        height: 110,
                        child: ListView.builder(
                          itemCount: _paradas.length,
                          itemBuilder: (context, index) {
                            bool entregue = _paradas[index]['entregue'] == true;

                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                radius: 12,
                                backgroundColor: entregue ? Colors.green.shade600 : const Color(0xFF1A73E8),
                                child: entregue
                                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                                    : Text(
                                        '${index + 1}',
                                        style: const TextStyle(color: Colors.white, fontSize: 11),
                                      ),
                              ),
                              title: Text(
                                _paradas[index]['endereco'],
                                style: TextStyle(
                                  decoration: entregue ? TextDecoration.lineThrough : null,
                                  color: entregue ? Colors.grey : Colors.black87,
                                  fontSize: 13,
                                ),
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  entregue ? Icons.check_box : Icons.check_box_outline_blank,
                                  color: entregue ? Colors.green : Colors.grey,
                                  size: 20,
                                ),
                                onPressed: () => _marcarComoEntregue(index),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class TelaLeitorScanner extends StatefulWidget {
  const TelaLeitorScanner({super.key});

  @override
  State<TelaLeitorScanner> createState() => _TelaLeitorScannerState();
}

class _TelaLeitorScannerState extends State<TelaLeitorScanner> {
  late final MobileScannerController _controller;
  bool _jaDetectou = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      autoStart: true,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Escanear Pacote'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_jaDetectou) return;
              final barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
                  _jaDetectou = true;
                  Navigator.pop(context, barcode.rawValue);
                  break;
                }
              }
            },
          ),
          Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.greenAccent, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const Positioned(
            bottom: 30,
            child: Card(
              color: Colors.black87,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Aponte para o código de barras ou QR Code',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
