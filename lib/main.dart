import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const CircuitoEntregasApp());
}

class CircuitoEntregasApp extends StatelessWidget {
  const CircuitoEntregasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Otimize Entregas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return const OtimizeHomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha todos os campos.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Erro de autenticação.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F0FE),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.navigation_rounded, size: 70, color: Color(0xFF1A73E8)),
              const SizedBox(height: 8),
              const Text(
                'Otimize',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF202124)),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'E-mail',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Senha',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A73E8),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        _isLogin ? 'Entrar' : 'Cadastrar',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
              TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(
                  _isLogin ? 'Não tem conta? Cadastre-se' : 'Já tem conta? Entrar',
                  style: const TextStyle(color: Color(0xFF1A73E8), fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OtimizeHomeScreen extends StatefulWidget {
  const OtimizeHomeScreen({super.key});

  @override
  State<OtimizeHomeScreen> createState() => _OtimizeHomeScreenState();
}

class _OtimizeHomeScreenState extends State<OtimizeHomeScreen> {
  final MapController _mapController = MapController();
  final _user = FirebaseAuth.instance.currentUser;
  LatLng? _currentPosition;
  double _currentHeading = 0.0;
  List<LatLng> _routePoints = [];
  String _lastRouteHash = '';
  final ImagePicker _picker = ImagePicker();
  bool _isProcessingImage = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    final pos = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _currentPosition = LatLng(pos.latitude, pos.longitude);
        _currentHeading = pos.heading;
      });
      _mapController.move(_currentPosition!, 14.2);
    }

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 3,
      ),
    ).listen((Position p) {
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(p.latitude, p.longitude);
          if (p.heading != 0) _currentHeading = p.heading;
        });
      }
    });
  }

  Future<LatLng?> _geocodeHighPrecision(String input) async {
    String cleanInput = input.trim();
    
    final cepPattern = RegExp(r'(\d{5})-?(\d{3})');
    final match = cepPattern.firstMatch(cleanInput);
    if (match != null) {
      final cep = '${match.group(1)}${match.group(2)}';
      try {
        final cepRes = await http.get(Uri.parse('https://viacep.com.br/ws/$cep/json/'));
        if (cepRes.statusCode == 200) {
          final cepData = json.decode(cepRes.body);
          if (cepData['erro'] != true) {
            final logradouro = cepData['logradouro'] ?? '';
            final localidade = cepData['localidade'] ?? '';
            final uf = cepData['uf'] ?? '';
            cleanInput = '$logradouro, $localidade - $uf, Brasil';
          }
        }
      } catch (_) {}
    }

    try {
      final query = cleanInput.contains('Brasil') ? cleanInput : '$cleanInput, Brasil';
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&countrycodes=br&limit=1&addressdetails=1');
      final res = await http.get(url, headers: {'User-Agent': 'OtimizeDeliveryApp/1.0'});
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data is List && data.isNotEmpty) {
          return LatLng(
            double.parse(data[0]['lat']),
            double.parse(data[0]['lon']),
          );
        }
      }
    } catch (_) {}

    return null;
  }

  Future<void> _fetchStreetRoute(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return;
    final hash = waypoints.map((p) => '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}').join(';');
    if (hash == _lastRouteHash) return;
    _lastRouteHash = hash;

    try {
      final coords = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
      final url = Uri.parse('https://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final coordsList = data['routes'][0]['geometry']['coordinates'] as List;
        if (mounted) {
          setState(() {
            _routePoints = coordsList.map((c) => LatLng(c[1] as double, c[0] as double)).toList();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _openExternalDirections(LatLng target) async {
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${target.latitude},${target.longitude}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _startTurnByTurnGps(LatLng target) async {
    final navUrl = Uri.parse('google.navigation:q=${target.latitude},${target.longitude}&mode=d');
    final fallbackUrl = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${target.latitude},${target.longitude}');
    if (await canLaunchUrl(navUrl)) {
      await launchUrl(navUrl);
    } else if (await canLaunchUrl(fallbackUrl)) {
      await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
    }
  }

  void _showAddModal({String initialCode = ''}) {
    final addressCtrl = TextEditingController(text: initialCode);
    final complementCtrl = TextEditingController();
    bool isSearching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Confirmar Destino do Pacote',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF202124)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Destino Lido da Etiqueta',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: complementCtrl,
                decoration: const InputDecoration(
                  labelText: 'Complemento / Nome do cliente (opcional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: () async {
                        final addr = addressCtrl.text.trim();
                        if (addr.isEmpty) return;

                        setModalState(() => isSearching = true);

                        LatLng? coords = await _geocodeHighPrecision(addr);

                        if (coords == null) {
                          final baseLat = _currentPosition?.latitude ?? -23.3228;
                          final baseLng = _currentPosition?.longitude ?? -46.7275;
                          coords = LatLng(baseLat, baseLng);
                        }

                        await FirebaseFirestore.instance.collection('deliveries').add({
                          'userId': _user?.uid,
                          'address': addr,
                          'complement': complementCtrl.text.trim(),
                          'status': 'pendente',
                          'lat': coords.latitude,
                          'lng': coords.longitude,
                          'createdAt': FieldValue.serverTimestamp(),
                        });

                        _lastRouteHash = '';
                        if (mounted) Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A73E8),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Adicionar à Rota', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // LEITOR DE ETIQUETA VIA CÂMERA (OCR Rápido)
  Future<void> _scanDestinationLabel() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (image == null) return;

    setState(() => _isProcessingImage = true);

    try {
      final bytes = await image.readAsBytes();
      final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';

      final response = await http.post(
        Uri.parse('https://api.ocr.space/parse/image'),
        body: {
          'apikey': 'helloworld',
          'language': 'por',
          'base64Image': base64Image,
        },
      );

      String parsedText = '';
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['ParsedResults'] != null && data['ParsedResults'].isNotEmpty) {
          parsedText = data['ParsedResults'][0]['ParsedText'] ?? '';
        }
      }

      String destination = '';
      bool targetFound = false;

      for (var line in parsedText.split('\n')) {
        final lower = line.toLowerCase().trim();
        if (lower.contains('destino') || lower.contains('endereço') || lower.contains('destinatario')) {
          targetFound = true;
          destination = '';
          continue;
        }
        if (targetFound || lower.contains('rua') || lower.contains('av') || lower.contains('alameda') || RegExp(r'\d{5}-\d{3}').hasMatch(line)) {
          destination += '$line ';
        }
      }

      if (destination.trim().isEmpty && parsedText.trim().isNotEmpty) {
        destination = parsedText.split('\n').take(3).join(' ');
      }

      if (mounted) {
        setState(() => _isProcessingImage = false);
        _showAddModal(initialCode: destination.trim());
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isProcessingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falha ao processar foto. Digite manualmente.')),
        );
        _showAddModal();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultPos = const LatLng(-23.3228, -46.7275);
    final mapCenter = _currentPosition ?? defaultPos;

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('deliveries')
            .where('userId', isEqualTo: _user?.uid)
            .snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          final list = List.from(docs);

          List<LatLng> waypoints = [];
          if (_currentPosition != null) waypoints.add(_currentPosition!);

          for (var item in list) {
            final data = item.data() as Map<String, dynamic>;
            if (data['status'] == 'pendente') {
              waypoints.add(LatLng(data['lat'] ?? 0.0, data['lng'] ?? 0.0));
            }
          }

          if (waypoints.length > 1) {
            _fetchStreetRoute(waypoints);
          }

          List<Marker> markers = [];
          if (_currentPosition != null) {
            markers.add(
              Marker(
                point: _currentPosition!,
                width: 60,
                height: 60,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A73E8).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Transform.rotate(
                      angle: (_currentHeading * (math.pi / 180)),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1A73E8),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                        ),
                        child: const Center(
                          child: Icon(Icons.navigation, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          for (int i = 0; i < list.length; i++) {
            final data = list[i].data() as Map<String, dynamic>;
            final pt = LatLng(data['lat'] ?? 0.0, data['lng'] ?? 0.0);

            markers.add(
              Marker(
                point: pt,
                width: 38,
                height: 38,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF9E9E9E),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ),
            );
          }

          final pendingStop = list.cast<QueryDocumentSnapshot?>().firstWhere(
                (doc) => (doc?.data() as Map<String, dynamic>)['status'] == 'pendente',
                orElse: () => null,
              );

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: mapCenter,
                  initialZoom: 14.2,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                    userAgentPackageName: 'com.example.app_entregas',
                  ),
                  if (_routePoints.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _routePoints,
                          color: const Color(0xFF2979FF),
                          strokeWidth: 5.0,
                        ),
                      ],
                    ),
                  MarkerLayer(markers: markers),
                ],
              ),
              if (_isProcessingImage)
                Container(
                  color: Colors.black45,
                  child: const Center(
                    child: Card(
                      color: Colors.white,
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Lendo destino da etiqueta...'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 16,
                bottom: 370,
                child: Column(
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'pkgBtn',
                      onPressed: () => _showAddModal(),
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFF57C00),
                      child: const Icon(Icons.inventory_2_outlined),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'navBtn',
                      onPressed: () {
                        if (_currentPosition != null) {
                          _mapController.move(_currentPosition!, 15.5);
                        }
                      },
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1A73E8),
                      child: const Icon(Icons.near_me_outlined),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 350,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, -4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 10, bottom: 12),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 46,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F3F4),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.search, color: Colors.grey, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Adicione ou busque',
                                      style: TextStyle(color: Colors.black54, fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            InkWell(
                              onTap: () => _showAddModal(),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFA000),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.inventory_2, color: Colors.white, size: 22),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _scanDestinationLabel,
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A73E8),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.camera_alt, color: Colors.white, size: 22),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Término 14:37 • ${list.length} paradas • 4.80 km',
                              style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'São Paulo / Franco da Rocha',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF202124)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  if (pendingStop != null) {
                                    final d = pendingStop.data() as Map<String, dynamic>;
                                    _openExternalDirections(LatLng(d['lat'] ?? 0.0, d['lng'] ?? 0.0));
                                  }
                                },
                                icon: const Icon(Icons.map_outlined, size: 18, color: Color(0xFF1A73E8)),
                                label: const Text(
                                  'Abrir Maps',
                                  style: TextStyle(color: Color(0xFF1A73E8), fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.grey, width: 0.8),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  if (pendingStop != null) {
                                    final d = pendingStop.data() as Map<String, dynamic>;
                                    _startTurnByTurnGps(LatLng(d['lat'] ?? 0.0, d['lng'] ?? 0.0));
                                  }
                                },
                                icon: const Icon(Icons.navigation, size: 18, color: Colors.white),
                                label: const Text(
                                  'Navegar',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1A73E8),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 20, thickness: 0.8),
                      Expanded(
                        child: list.isEmpty
                            ? const Center(
                                child: Text('Nenhuma entrega pendente', style: TextStyle(color: Colors.grey)),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: list.length,
                                itemBuilder: (context, index) {
                                  final data = list[index].data() as Map<String, dynamic>;
                                  final docId = list[index].id;
                                  final isDone = data['status'] == 'concluido';
                                  final target = LatLng(data['lat'] ?? 0.0, data['lng'] ?? 0.0);

                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Column(
                                        children: [
                                          InkWell(
                                            onTap: () {
                                              FirebaseFirestore.instance.collection('deliveries').doc(docId).update({
                                                'status': isDone ? 'pendente' : 'concluido',
                                              });
                                            },
                                            child: Container(
                                              width: 24,
                                              height: 24,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF4CAF50),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.check, color: Colors.white, size: 16),
                                            ),
                                          ),
                                          if (index < list.length - 1)
                                            Container(
                                              width: 2,
                                              height: 36,
                                              color: Colors.grey.shade300,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              data['address'] ?? '',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                decoration: isDone ? TextDecoration.lineThrough : null,
                                                color: isDone ? Colors.grey : const Color(0xFF202124),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              data['complement'] ?? '',
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.directions, color: Color(0xFF1A73E8), size: 22),
                                        onPressed: () => _openExternalDirections(target),
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
