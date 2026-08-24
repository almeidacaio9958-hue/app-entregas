import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const AppEntregasProfissional());
}

class AppEntregasProfissional extends StatelessWidget {
  const AppEntregasProfissional({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Circuit Navigation Pro',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorSchemeSeed: const Color(0xFF1A73E8),
        scaffoldBackgroundColor: const Color(0xFFF1F4F9),
      ),
      home: const TelaPrincipalNavegacao(),
    );
  }
}

class TelaPrincipalNavegacao extends StatefulWidget {
  const TelaPrincipalNavegacao({super.key});

  @override
  State<TelaPrincipalNavegacao> createState() => _TelaPrincipalNavegacaoState();
}

class _TelaPrincipalNavegacaoState extends State<TelaPrincipalNavegacao> {
  final MapController _mapController = MapController();
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  LatLng _posicaoAtual = const LatLng(-23.328000, -46.732000);
  StreamSubscription<Position>? _streamPosicao;
  double _velocidadeKmH = 0.0;
  double _anguloDirecao = 0.0;

  bool _modoNavegacao = false;
  bool _cardEntregaExpandido = true;
  bool _calculando = false;

  List<LatLng> _geometriaRota = [];
  String _distanciaFormatada = '0.0 km';
  String _tempoRestante = '0 min';
  String _previsaoChegada = '00:00';
  String _proximaManobraTexto = 'Siga em frente';

  final List<Map<String, dynamic>> _listaParadas = [
    {
      'endereco': 'R. Joaquim Floriano, 834',
      'bairro': 'Itaim Bibi, 04537-011',
      'tipo': 'Pequeno',
      'pacote': 'Sacola',
      'latLng': const LatLng(-23.332000, -46.736000),
      'entregue': false,
      'horario': '09:00',
    },
    {
      'endereco': 'R. Bandeira Paulista, 520',
      'bairro': 'Itaim Bibi, 04537-011',
      'tipo': 'Médio',
      'pacote': 'Caixa',
      'latLng': const LatLng(-23.340000, -46.742000),
      'entregue': false,
      'horario': '09:24',
    },
  ];

  @override
  void initState() {
    super.initState();
    _iniciarGpsNativo();
    _recalcularRotaCompleta();
  }

  @override
  void dispose() {
    _streamPosicao?.cancel();
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _iniciarGpsNativo() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    try {
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _posicaoAtual = LatLng(pos.latitude, pos.longitude);
      });
      _mapController.move(_posicaoAtual, 16.0);
    } catch (_) {}

    const settings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2);
    _streamPosicao = Geolocator.getPositionStream(locationSettings: settings).listen((Position pos) {
      setState(() {
        _posicaoAtual = LatLng(pos.latitude, pos.longitude);
        _velocidadeKmH = math.max(0.0, (pos.speed * 3.6));
        if (pos.heading != 0) {
          _anguloDirecao = pos.heading * (math.pi / 180.0);
        }
      });

      if (_modoNavegacao) {
        _mapController.moveAndRotate(_posicaoAtual, 17.5, pos.heading != 0 ? -pos.heading : 0.0);
      }
    });
  }

  Future<void> _recalcularRotaCompleta() async {
    final pendentes = _listaParadas.where((p) => !p['entregue']).toList();
    if (pendentes.isEmpty) {
      setState(() => _geometriaRota = []);
      return;
    }

    setState(() => _calculando = true);
    final destino = pendentes.first['latLng'] as LatLng;
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${_posicaoAtual.longitude},${_posicaoAtual.latitude};'
      '${destino.longitude},${destino.latitude}'
      '?overview=full&geometries=geojson&steps=true',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coords = data['routes'][0]['geometry']['coordinates'] as List;
        final double distanciaMetros = data['routes'][0]['distance'].toDouble();
        final double duracaoSegundos = data['routes'][0]['duration'].toDouble();

        final steps = data['routes'][0]['legs'][0]['steps'] as List;
        String proximaRua = 'Siga até o destino';
        if (steps.length > 1) {
          proximaRua = steps[1]['name'] ?? 'Mantenha-se na via';
          if (proximaRua.trim().isEmpty) proximaRua = 'Vire na próxima via';
        }

        final agora = DateTime.now();
        final chegada = agora.add(Duration(seconds: duracaoSegundos.round()));
        final formatChegada = '${chegada.hour.toString().padLeft(2, '0')}:${chegada.minute.toString().padLeft(2, '0')}';

        setState(() {
          _geometriaRota = coords.map((c) => LatLng(c[1], c[0])).toList();
          _distanciaFormatada = '${(distanciaMetros / 1000).toStringAsFixed(2)} km';
          _tempoRestante = '${(duracaoSegundos / 60).round()} min';
          _previsaoChegada = formatChegada;
          _proximaManobraTexto = proximaRua;
          _calculando = false;
        });
      }
    } catch (_) {
      setState(() => _calculando = false);
    }
  }

  void _abrirNoGoogleMapsExterno(LatLng destino) async {
    final url = Uri.parse('google.navigation:q=${destino.latitude},${destino.longitude}&mode=d');
    final fallbackUrl = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${destino.latitude},${destino.longitude}');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
    }
  }

  void _iniciarModoDirecao() {
    setState(() {
      _modoNavegacao = true;
      _cardEntregaExpandido = true;
    });
    _mapController.moveAndRotate(_posicaoAtual, 17.5, -(_anguloDirecao * 180 / math.pi));
  }

  void _sairModoDirecao() {
    setState(() {
      _modoNavegacao = false;
    });
    _mapController.moveAndRotate(_posicaoAtual, 15.5, 0.0);
  }

  Future<void> _escanearEtiquetaOCR() async {
    await Permission.camera.request();
    try {
      final XFile? foto = await _picker.pickImage(source: ImageSource.camera, imageQuality: 95);
      if (foto == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lendo etiqueta e identificando destinatário...')),
      );

      final inputImage = InputImage.fromFilePath(foto.path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      String texto = recognizedText.text;

      final linhas = texto.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      String enderecoFinal = '';
      String cep = '';

      final cepMatch = RegExp(r'(?:CEP:?\s*)?(\d{5}-?\d{3}|\d{8})').firstMatch(texto);
      if (cepMatch != null) {
        cep = cepMatch.group(1)!.replaceAll('-', '');
      }

      for (int i = 0; i < linhas.length; i++) {
        final l = linhas[i];
        final lLow = l.toLowerCase();
        if (lLow.startsWith('endereço:') || lLow.startsWith('endereco:')) {
          enderecoFinal = l.replaceFirst(RegExp(r'endere[çc]o:\s*', caseSensitive: false), '').trim();
          break;
        } else if (enderecoFinal.isEmpty && i > 2 && (lLow.contains('rua ') || lLow.contains('av.'))) {
          enderecoFinal = l;
        }
      }

      if (enderecoFinal.isEmpty && cep.isNotEmpty) {
        enderecoFinal = 'Entrega CEP $cep';
      }

      _confirmarAdicaoManual(enderecoFinal, cep);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao ler: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _confirmarAdicaoManual(String endereco, String cep) {
    final ctrl = TextEditingController(text: endereco);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          top: 20,
          left: 20,
          right: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Confirmar Parada', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: 'Endereço',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _listaParadas.add({
                      'endereco': ctrl.text.trim(),
                      'bairro': 'São Paulo',
                      'tipo': 'Pequeno',
                      'pacote': 'Caixa',
                      'latLng': LatLng(_posicaoAtual.latitude + 0.004, _posicaoAtual.longitude + 0.004),
                      'entregue': false,
                      'horario': '10:15',
                    });
                  });
                  _recalcularRotaCompleta();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A73E8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Adicionar à Rota', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }

  void _finalizarParadaAtual(bool sucesso) {
    final index = _listaParadas.indexWhere((p) => !p['entregue']);
    if (index != -1) {
      setState(() {
        _listaParadas[index]['entregue'] = true;
      });
      _recalcularRotaCompleta();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sucesso ? 'Entrega concluída com sucesso! ✅' : 'Tentativa registrada como falha ❌'),
          backgroundColor: sucesso ? Colors.green.shade700 : Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final paradaAtiva = _listaParadas.firstWhere(
      (p) => !p['entregue'],
      orElse: () => {'endereco': 'Sem entregas pendentes', 'tipo': '-', 'pacote': '-', 'latLng': _posicaoAtual},
    );
    final totalParadas = _listaParadas.length;
    final concluidas = _listaParadas.where((p) => p['entregue']).length;
    final paradaAtualNum = math.min(totalParadas, concluidas + 1);

    // Marcador Navegador/Veículo
    final markerCarro = Marker(
      point: _posicaoAtual,
      width: 60,
      height: 60,
      child: Transform.rotate(
        angle: _anguloDirecao,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF1A73E8),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: const Icon(Icons.navigation, color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );

    // Marcadores Paradas numeradas
    final markersParadas = _listaParadas.asMap().entries.map((entry) {
      final idx = entry.key;
      final parada = entry.value;
      final bool entregue = parada['entregue'] == true;

      return Marker(
        point: parada['latLng'] as LatLng,
        width: 44,
        height: 48,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: entregue ? Colors.grey.shade400 : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: entregue ? Colors.grey : const Color(0xFF1A73E8), width: 2),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: Text(
                '${idx + 1}',
                style: TextStyle(
                  color: entregue ? Colors.grey.shade700 : const Color(0xFF1A73E8),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: entregue ? Colors.grey : const Color(0xFF1A73E8), size: 16),
          ],
        ),
      );
    }).toList();

    return Scaffold(
      body: Stack(
        children: [
          // 1. MAPA COM CAMADA DO GOOGLE MAPS (GRATUITA / SEM CHAVE)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _posicaoAtual,
              initialZoom: 15.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                subdomains: const ['0', '1', '2', '3'],
                userAgentPackageName: 'com.google.android.apps.maps',
              ),
              if (_geometriaRota.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _geometriaRota,
                      color: const Color(0xFF1A73E8),
                      strokeWidth: _modoNavegacao ? 7.0 : 5.0,
                    ),
                  ],
                ),
              MarkerLayer(markers: [markerCarro, ...markersParadas]),
            ],
          ),

          // 2. MODO NAVEGAÇÃO: Placa Superior
          if (_modoNavegacao)
            Positioned(
              top: 40,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF181F2C),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.turn_right_rounded, color: Colors.white, size: 40),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _distanciaFormatada,
                            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            _proximaManobraTexto,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          const Icon(Icons.flag, color: Colors.white70, size: 14),
                          const SizedBox(width: 4),
                          Text(_previsaoChegada, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 3. Botões Flutuantes Laterais
          Positioned(
            right: 16,
            bottom: _modoNavegacao ? (_cardEntregaExpandido ? 240 : 90) : 340,
            child: Column(
              children: [
                _botaoCircular(Icons.directions, () {
                  _abrirNoGoogleMapsExterno(paradaAtiva['latLng'] as LatLng);
                }, corIcone: Colors.blueAccent),
                const SizedBox(height: 10),
                _botaoCircular(Icons.navigation, () {
                  _mapController.moveAndRotate(_posicaoAtual, 17.5, _modoNavegacao ? -(_anguloDirecao * 180 / math.pi) : 0.0);
                }, corIcone: const Color(0xFF1A73E8)),
              ],
            ),
          ),

          // Velocímetro (km/h)
          Positioned(
            left: 16,
            bottom: _modoNavegacao ? (_cardEntregaExpandido ? 240 : 90) : 340,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black12),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${_velocidadeKmH.round()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const Text('km/h', style: TextStyle(fontSize: 8, color: Colors.grey)),
                ],
              ),
            ),
          ),

          // 4. MODO NAVEGAÇÃO: Card de Entrega e Barra Preta Inferior
          if (_modoNavegacao)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                children: [
                  if (_cardEntregaExpandido)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  paradaAtiva['endereco'] ?? '',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF181F2C)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                                onPressed: () => setState(() => _cardEntregaExpandido = false),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text('$paradaAtualNum/$totalParadas  ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              const Icon(Icons.inventory_2_outlined, size: 14, color: Colors.grey),
                              Text(' ${paradaAtiva['tipo']}  ', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                              const Icon(Icons.shopping_bag_outlined, size: 14, color: Colors.grey),
                              Text(' ${paradaAtiva['pacote']}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _finalizarParadaAtual(false),
                                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                                  label: const Text('Falhou', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: Colors.red.shade200),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _finalizarParadaAtual(true),
                                  icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                                  label: const Text('Entregue', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade50,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Container(
                    color: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 26),
                          onPressed: _sairModoDirecao,
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _cardEntregaExpandido = !_cardEntregaExpandido),
                          child: Column(
                            children: [
                              Text(_tempoRestante, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                              Text('$_previsaoChegada • $_distanciaFormatada', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.menu, color: Colors.white, size: 26),
                          onPressed: _sairModoDirecao,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // 5. MODO LISTA / OTIMIZE (Painel de Paradas)
          if (!_modoNavegacao)
            DraggableScrollableSheet(
              initialChildSize: 0.38,
              minChildSize: 0.18,
              maxChildSize: 0.85,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -3))],
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(18),
                    children: [
                      Center(
                        child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
                      ),
                      const SizedBox(height: 14),

                      // Barra de Busca e Ações
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              height: 44,
                              decoration: BoxDecoration(color: const Color(0xFFF1F4F9), borderRadius: BorderRadius.circular(12)),
                              child: const Row(
                                children: [
                                  Icon(Icons.search, color: Colors.grey, size: 20),
                                  SizedBox(width: 8),
                                  Text('Adicione ou busque', style: TextStyle(color: Colors.grey, fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filled(
                            onPressed: _escanearEtiquetaOCR,
                            icon: const Icon(Icons.camera_alt),
                            style: IconButton.styleFrom(backgroundColor: const Color(0xFF1A73E8)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      Text('Término $_previsaoChegada • $totalParadas paradas • $_distanciaFormatada', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const Text('São Paulo / Franco da Rocha', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                if (_listaParadas.isNotEmpty) {
                                  _abrirNoGoogleMapsExterno(_listaParadas.first['latLng']);
                                }
                              },
                              icon: const Icon(Icons.map, size: 16),
                              label: const Text('Abrir Maps', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _iniciarModoDirecao,
                              icon: const Icon(Icons.navigation, size: 16),
                              label: const Text('Navegar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A73E8),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 28),

                      // Lista com Timeline
                      ..._listaParadas.asMap().entries.map((entry) {
                        final i = entry.key;
                        final p = entry.value;
                        final bool entregue = p['entregue'] == true;

                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundColor: entregue ? Colors.green : const Color(0xFF1A73E8),
                                    child: entregue
                                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                                        : Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                  if (i != _listaParadas.length - 1)
                                    Expanded(
                                      child: Container(width: 2, color: Colors.blue.shade100),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 20.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p['endereco'],
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          decoration: entregue ? TextDecoration.lineThrough : null,
                                        ),
                                      ),
                                      Text(p['bairro'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.directions, color: Color(0xFF1A73E8), size: 20),
                                onPressed: () => _abrirNoGoogleMapsExterno(p['latLng']),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _botaoCircular(IconData icone, VoidCallback onTap, {Color corIcone = const Color(0xFF181F2C)}) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: IconButton(icon: Icon(icone, color: corIcone, size: 20), onPressed: onTap),
    );
  }
}
