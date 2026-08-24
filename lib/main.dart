import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
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
        SnackBar(content: Text(e.message ?? 'Ocorreu um erro no acesso.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFC5D9F8),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.route, size: 70, color: Color(0xFF0F2537)),
              const SizedBox(height: 8),
              const Text(
                'Otimize',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: Color(0xFF0F2537),
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
                        backgroundColor: const Color(0xFF0F2537),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        _isLogin ? 'Entrar no Sistema' : 'Cadastrar Motorista',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
              TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(
                  _isLogin ? 'Novo por aqui? Criar conta' : 'Já possui conta? Acessar',
                  style: const TextStyle(color: Color(0xFF0F2537), fontWeight: FontWeight.w600),
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
  final _user = FirebaseAuth.instance.currentUser;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    final position = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
      _mapController.move(_currentPosition!, 14.0);
    }
  }

  double _calculateDistance(LatLng p1, LatLng p2) {
    const p = 0.017453292519943295;
    final c = math.cos;
    final a = 0.5 -
        c((p2.latitude - p1.latitude) * p) / 2 +
        c(p1.latitude * p) * c(p2.latitude * p) * (1 - c((p2.longitude - p1.longitude) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a));
  }

  Future<void> _openExternalMap(String address) async {
    final query = Uri.encodeComponent(address);
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _showAddModal({String initialCode = ''}) {
    final addressCtrl = TextEditingController(text: initialCode);
    final complementCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
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
              'Adicionar Nova Entrega',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F2537)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressCtrl,
              decoration: const InputDecoration(
                labelText: 'Endereço completo / Código escaneado',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: complementCtrl,
              decoration: const InputDecoration(
                labelText: 'Destinatário / Observação (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final addr = addressCtrl.text.trim();
                if (addr.isEmpty) return;

                final baseLat = _currentPosition?.latitude ?? -23.5505;
                final baseLng = _currentPosition?.longitude ?? -46.6333;
                final offset = (DateTime.now().millisecond % 40) * 0.0012;

                await FirebaseFirestore.instance.collection('deliveries').add({
                  'userId': _user?.uid,
                  'address': addr,
                  'complement': complementCtrl.text.trim(),
                  'status': 'pendente',
                  'lat': baseLat + offset,
                  'lng': baseLng + offset,
                  'createdAt': FieldValue.serverTimestamp(),
                });

                if (mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F2537),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Confirmar Parada'),
            ),
          ],
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
            backgroundColor: const Color(0xFF0F2537),
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
    final defaultLocation = const LatLng(-23.5505, -46.6333);
    final centerMap = _currentPosition ?? defaultLocation;

    return Scaffold(
      backgroundColor: const Color(0xFFC5D9F8),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.logout, color: Color(0xFF0F2537)),
                    onPressed: () => FirebaseAuth.instance.signOut(),
                  ),
                  const Text(
                    'Otimize',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF0F2537)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF0F2537)),
                    onPressed: _openScanner,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
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

                      List<LatLng> routePoints = [];
                      if (_currentPosition != null) routePoints.add(_currentPosition!);

                      List<Marker> markers = [];
                      if (_currentPosition != null) {
                        markers.add(
                          Marker(
                            point: _currentPosition!,
                            width: 38,
                            height: 38,
                            child: const Icon(Icons.navigation, color: Colors.blue, size: 32),
                          ),
                        );
                      }

                      for (int i = 0; i < list.length; i++) {
                        final data = list[i].data() as Map<String, dynamic>;
                        final point = LatLng(data['lat'] ?? 0.0, data['lng'] ?? 0.0);
                        routePoints.add(point);
                        final isDone = data['status'] == 'concluido';

                        markers.add(
                          Marker(
                            point: point,
                            width: 32,
                            height: 32,
                            child: CircleAvatar(
                              backgroundColor: isDone ? Colors.green : const Color(0xFF0F2537),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        );
                      }

                      return Column(
                        children: [
                          // MAPA COM ROTA TRAÇADA
                          Expanded(
                            flex: 5,
                            child: FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: centerMap,
                                initialZoom: 14.0,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.example.app_entregas',
                                ),
                                if (routePoints.length > 1)
                                  PolylineLayer(
                                    polylines: [
                                      Polyline(
                                        points: routePoints,
                                        color: const Color(0xFF1E3A8A),
                                        strokeWidth: 4.0,
                                      ),
                                    ],
                                  ),
                                MarkerLayer(markers: markers),
                              ],
                            ),
                          ),

                          // PAINEL DE CONTROLE DAS ENTREGAS
                          Expanded(
                            flex: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                boxShadow: [
                                  BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -4)),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${list.length} Paradas • Circuito Otimizado',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F2537),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle, color: Color(0xFF0F2537), size: 30),
                                        onPressed: () => _showAddModal(),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 8),
                                  if (list.isEmpty)
                                    const Expanded(
                                      child: Center(
                                        child: Text(
                                          'Nenhuma entrega na rota.\nEscaneie uma encomenda para iniciar.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                    )
                                  else
                                    Expanded(
                                      child: ListView.builder(
                                        itemCount: list.length,
                                        itemBuilder: (context, index) {
                                          final data = list[index].data() as Map<String, dynamic>;
                                          final docId = list[index].id;
                                          final isDone = data['status'] == 'concluido';

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
                                            },
                                            child: ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              leading: CircleAvatar(
                                                backgroundColor: isDone ? Colors.green : const Color(0xFF0F2537),
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
                                              subtitle: Text(
                                                data['complement'] != null && data['complement'].toString().isNotEmpty
                                                    ? data['complement']
                                                    : (isDone ? 'Concluído' : 'Pendente'),
                                              ),
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.navigation, color: Colors.blue),
                                                    onPressed: () => _openExternalMap(data['address']),
                                                  ),
                                                  IconButton(
                                                    icon: Icon(
                                                      isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                                                      color: isDone ? Colors.green : Colors.grey,
                                                    ),
                                                    onPressed: () {
                                                      FirebaseFirestore.instance.collection('deliveries').doc(docId).update({
                                                        'status': isDone ? 'pendente' : 'concluido',
                                                      });
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
