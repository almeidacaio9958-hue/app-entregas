import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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
      title: 'Otimize',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
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
          return const OtimizeScreen();
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
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF202124),
                ),
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

class OtimizeScreen extends StatefulWidget {
  const OtimizeScreen({super.key});

  @override
  State<OtimizeScreen> createState() => _OtimizeScreenState();
}

class _OtimizeScreenState extends State<OtimizeScreen> {
  LatLng? _currentPosition;
  double _currentHeading = 0.0;
  final _user = FirebaseAuth.instance.currentUser;
  final MapController _mapController = MapController();
  List<LatLng> _streetRoutePoints = [];
  String _lastRouteKey = '';
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _startLocationTracking() async {
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
      _mapController.move(_currentPosition!, 14.5);
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          if (position.heading != 0.0) _currentHeading = position.heading;
        });
      }
    });
  }

  Future<LatLng?> _geocodeAddress(String query) async {
    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1');
      final res = await http.get(url, headers: {'User-Agent': 'OtimizeApp/1.0'});
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

  // Traça a rota exata nas ruas
  Future<void> _fetchStreetRoute(List<LatLng> points) async {
    if (points.length < 2) return;

    final key = points
        .map((p) => '${p.latitude.toStringAsFixed(3)},${p.longitude.toStringAsFixed(3)}')
        .join(';');
    if (key == _lastRouteKey) return;
    _lastRouteKey = key;

    try {
      final coords = points.map((p) => '${p.longitude},${p.latitude}').join(';');
      final url = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final coordsList = data['routes'][0]['geometry']['coordinates'] as List;
        if (mounted) {
          setState(() {
            _streetRoutePoints = coordsList
                .map((c) => LatLng(c[1] as double, c[0] as double))
                .toList();
          });
        }
      }
    } catch (_) {}
  }

  double _calculateDistance(LatLng p1, LatLng p2) {
    const p = 0.017453292519943295;
    final c = math.cos;
    final a = 0.5 -
        c((p2.latitude - p1.latitude) * p) / 2 +
        c(p1.latitude * p) * c(p2.latitude * p) * (1 - c((p2.longitude - p1.longitude) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a));
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
                'Adicionar Endereço na Rota',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF202124)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Endereço (Ex: Rua Tapuias, Franco da Rocha)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_searching),
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
                  : ElevatedButton.icon(
                      onPressed: () async {
                        final addr = addressCtrl.text.trim();
                        if (addr.isEmpty) return;

                        setModalState(() => isSearching = true);

                        LatLng? coords = await _geocodeAddress(addr);
                        if (coords == null) {
                          final baseLat = _currentPosition?.latitude ?? -23.3228;
                          final baseLng = _currentPosition?.longitude ?? -46.7275;
                          final offset = (DateTime.now().millisecond % 30) * 0.002;
                          coords = LatLng(baseLat + offset, baseLng + offset);
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

                        _lastRouteKey = '';
                        if (mounted) Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.add_location_alt),
                      label: const Text('Salvar Parada'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A73E8),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  void _openScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('Escanear Pacote'),
            backgroundColor: const Color(0xFF1A73E8),
            foregroundColor: Colors.white,
          ),
          body: MobileScanner(
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                final code = barcode.rawValue;
                if (code != null && code.isNotEmpty) {
                  Navigator.pop(ctx);
                  _showAddModal(initialCode: code);
                  break;
                }
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final defaultLocation = const LatLng(-23.3228, -46.7275);
    final centerMap = _currentPosition ?? defaultLocation;

    return Scaffold(
      backgroundColor: const Color(0xFFE8F0FE),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('deliveries')
              .where('userId', isEqualTo: _user?.uid)
              .snapshots(),
          builder: (context, snapshot) {
            final docs = snapshot.data?.docs ?? [];
            final list = List.from(docs);

            if (_currentPosition != null) {
              list.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                final posA = LatLng(dataA['lat'] ?? 0.0, dataA['lng'] ?? 0.0);
                final posB = LatLng(dataB['lat'] ?? 0.0, dataB['lng'] ?? 0.0);
                return _calculateDistance(_currentPosition!, posA)
                    .compareTo(_calculateDistance(_currentPosition!, posB));
              });
            }

            final nextStop = list.cast<QueryDocumentSnapshot?>().firstWhere(
                  (doc) => (doc?.data() as Map<String, dynamic>)['status'] == 'pendente',
                  orElse: () => null,
                );

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
                  width: 48,
                  height: 48,
                  child: Transform.rotate(
                    angle: (_currentHeading * (math.pi / 180)),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A73E8).withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.navigation, color: Color(0xFF1A73E8), size: 30),
                      ),
                    ),
                  ),
                ),
              );
            }

            for (int i = 0; i < list.length; i++) {
              final data = list[i].data() as Map<String, dynamic>;
              final pt = LatLng(data['lat'] ?? 0.0, data['lng'] ?? 0.0);
              final isDone = data['status'] == 'concluido';

              markers.add(
                Marker(
                  point: pt,
                  width: 38,
                  height: 38,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDone ? const Color(0xFF34A853) : const Color(0xFFEA4335),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              );
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.logout, color: Color(0xFF202124)),
                        onPressed: () => FirebaseAuth.instance.signOut(),
                      ),
                      const Text(
                        'Otimize',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF202124)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF1A73E8), size: 28),
                        onPressed: _openScanner,
                      ),
                    ],
                  ),
                ),
                // MAPA INTERNO COM AS RUAS E LINHA AZUL
                Expanded(
                  flex: 5,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      child: Stack(
                        children: [
                          FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: centerMap,
                              initialZoom: 15.0,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                                userAgentPackageName: 'com.example.app_entregas',
                              ),
                              if (_streetRoutePoints.isNotEmpty)
                                PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: _streetRoutePoints,
                                      color: const Color(0xFF1A73E8),
                                      strokeWidth: 6.0,
                                    ),
                                  ],
                                ),
                              MarkerLayer(markers: markers),
                            ],
                          ),
                          Positioned(
                            bottom: 16,
                            right: 16,
                            child: FloatingActionButton.small(
                              onPressed: () {
                                if (_currentPosition != null) {
                                  _mapController.move(_currentPosition!, 16.0);
                                }
                              },
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF1A73E8),
                              child: const Icon(Icons.my_location),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // LISTA DE ENTREGAS
                Expanded(
                  flex: 5,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -4)),
                      ],
                    ),
                    child: Column(
                      children: [
                        if (nextStop != null) ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                final d = nextStop.data() as Map<String, dynamic>;
                                final target = LatLng(d['lat'] ?? 0.0, d['lng'] ?? 0.0);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (ctx) => InAppNavigationScreen(
                                      target: target,
                                      address: d['address'] ?? '',
                                      docId: nextStop.id,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.navigation, color: Colors.white, size: 22),
                              label: const Text(
                                'INICIAR NAVEGAÇÃO INTERNA',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF34A853),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${list.length} Paradas na rota',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF202124)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle, color: Color(0xFF1A73E8), size: 30),
                              onPressed: () => _showAddModal(),
                            ),
                          ],
                        ),
                        const Divider(height: 6),
                        Expanded(
                          child: list.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Nenhuma entrega cadastrada.\nAdicione ou escaneie um pacote.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: list.length,
                                  itemBuilder: (context, index) {
                                    final data = list[index].data() as Map<String, dynamic>;
                                    final docId = list[index].id;
                                    final isDone = data['status'] == 'concluido';
                                    final target = LatLng(data['lat'] ?? 0.0, data['lng'] ?? 0.0);

                                    return Dismissible(
                                      key: Key(docId),
                                      direction: DismissDirection.endToStart,
                                      background: Container(
                                        alignment: Alignment.centerRight,
                                        padding: const EdgeInsets.only(right: 20),
                                        color: Colors.redAccent,
                                        child: const Icon(Icons.delete, color: Colors.white),
                                      ),
                                      onDismissed: (_) {
                                        FirebaseFirestore.instance.collection('deliveries').doc(docId).delete();
                                        _lastRouteKey = '';
                                      },
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: CircleAvatar(
                                          backgroundColor: isDone ? const Color(0xFF34A853) : const Color(0xFF1A73E8),
                                          child: Text(
                                            '${index + 1}',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        title: Text(
                                          data['address'] ?? '',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            decoration: isDone ? TextDecoration.lineThrough : null,
                                          ),
                                        ),
                                        subtitle: Text(data['complement'] ?? (isDone ? 'Concluído' : 'Pendente')),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.navigation, color: Color(0xFF1A73E8)),
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (ctx) => InAppNavigationScreen(
                                                      target: target,
                                                      address: data['address'] ?? '',
                                                      docId: docId,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                                                color: isDone ? const Color(0xFF34A853) : Colors.grey,
                                              ),
                                              onPressed: () {
                                                FirebaseFirestore.instance.collection('deliveries').doc(docId).update({
                                                  'status': isDone ? 'pendente' : 'concluido',
                                                });
                                                _lastRouteKey = '';
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
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
      ),
    );
  }
}

class InAppNavigationScreen extends StatefulWidget {
  final LatLng target;
  final String address;
  final String docId;

  const InAppNavigationScreen({
    super.key,
    required this.target,
    required this.address,
    required this.docId,
  });

  @override
  State<InAppNavigationScreen> createState() => _InAppNavigationScreenState();
}

class _InAppNavigationScreenState extends State<InAppNavigationScreen> {
  final MapController _navMapController = MapController();
  LatLng? _currentPosition;
  double _heading = 0.0;
  List<LatLng> _routePoints = [];
  StreamSubscription<Position>? _stream;

  @override
  void initState() {
    super.initState();
    _startLiveNavigation();
  }

  @override
  void dispose() {
    _stream?.cancel();
    super.dispose();
  }

  Future<void> _startLiveNavigation() async {
    final pos = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _currentPosition = LatLng(pos.latitude, pos.longitude);
        _heading = pos.heading;
      });
      _fetchStreetRoute();
    }

    _stream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          if (position.heading != 0.0) _heading = position.heading;
        });
        _navMapController.move(_currentPosition!, 17.0);
      }
    });
  }

  Future<void> _fetchStreetRoute() async {
    if (_currentPosition == null) return;
    try {
      final url = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/${_currentPosition!.longitude},${_currentPosition!.latitude};${widget.target.longitude},${widget.target.latitude}?overview=full&geometries=geojson');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final coords = data['routes'][0]['geometry']['coordinates'] as List;
        if (mounted) {
          setState(() {
            _routePoints = coords.map((c) => LatLng(c[1] as double, c[0] as double)).toList();
          });
        }
      }
    } catch (_) {}
  }

  double _getRemainingDistance() {
    if (_currentPosition == null) return 0.0;
    const p = 0.017453292519943295;
    final c = math.cos;
    final a = 0.5 -
        c((widget.target.latitude - _currentPosition!.latitude) * p) / 2 +
        c(_currentPosition!.latitude * p) * c(widget.target.latitude * p) * (1 - c((widget.target.longitude - _currentPosition!.longitude) * p)) / 2;
    return (12742 * math.asin(math.sqrt(a))) * 1000;
  }

  @override
  Widget build(BuildContext context) {
    final center = _currentPosition ?? widget.target;
    final distanceMeters = _getRemainingDistance();

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _navMapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 17.0,
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
                      color: const Color(0xFF1A73E8),
                      strokeWidth: 7.0,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_currentPosition != null)
                    Marker(
                      point: _currentPosition!,
                      width: 48,
                      height: 48,
                      child: Transform.rotate(
                        angle: (_heading * (math.pi / 180)),
                        child: const Icon(Icons.navigation, color: Color(0xFF1A73E8), size: 40),
                      ),
                    ),
                  Marker(
                    point: widget.target,
                    width: 44,
                    height: 44,
                    child: const Icon(Icons.location_on, color: Color(0xFFEA4335), size: 44),
                  ),
                ],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A73E8),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.directions, color: Colors.white, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            distanceMeters < 1000
                                ? 'Distância: ${distanceMeters.toStringAsFixed(0)} m'
                                : 'Distância: ${(distanceMeters / 1000).toStringAsFixed(1)} km',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            widget.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: ElevatedButton.icon(
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('deliveries')
                    .doc(widget.docId)
                    .update({'status': 'concluido'});
                if (mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.check_circle, color: Colors.white, size: 22),
              label: const Text(
                'CONCLUIR ENTREGA',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF34A853),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
