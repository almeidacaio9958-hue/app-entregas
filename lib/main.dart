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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F51B5)),
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
        SnackBar(content: Text(e.message ?? 'Ocorreu um erro.')),
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
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Otimize',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF0F2537)),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 24),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F2537),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(_isLogin ? 'Entrar' : 'Cadastrar'),
                    ),
              TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(
                  _isLogin ? 'Não tem conta? Cadastre-se' : 'Já tem conta? Faça login',
                  style: const TextStyle(color: Color(0xFF0F2537)),
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

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
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
    }
  }

  double _calculateDistance(LatLng p1, LatLng p2) {
    var p = 0.017453292519943295;
    var c = math.cos;
    var a = 0.5 - c((p2.latitude - p1.latitude) * p) / 2 +
        c(p1.latitude * p) * c(p2.latitude * p) *
            (1 - c((p2.longitude - p1.longitude) * p)) / 2;
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
              'Adicionar Nova Parada',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F2537)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressCtrl,
              decoration: const InputDecoration(
                labelText: 'Endereço / Pacote lido',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: complementCtrl,
              decoration: const InputDecoration(
                labelText: 'Complemento / Nome do cliente',
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

                await FirebaseFirestore.instance.collection('deliveries').add({
                  'userId': _user?.uid,
                  'address': addr,
                  'complement': complementCtrl.text.trim(),
                  'status': 'pendente',
                  'lat': baseLat + (DateTime.now().millisecond % 50) * 0.001,
                  'lng': baseLng + (DateTime.now().millisecond % 50) * 0.001,
                  'createdAt': FieldValue.serverTimestamp(),
                });

                if (mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F2537),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Salvar na Rota'),
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
            title: const Text('Escanear Código do Pacote'),
            backgroundColor: const Color(0xFF0F2537),
            foregroundColor: Colors.white,
          ),
          body: MobileScanner(
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              for (final barcode in barcodes) {
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
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF0F2537)),
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
                  child: Column(
                    children: [
                      Expanded(
                        flex: 5,
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: centerMap,
                            initialZoom: 14.0,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.example.app_entregas',
                            ),
                            MarkerLayer(
                              markers: [
                                if (_currentPosition != null)
                                  Marker(
                                    point: _currentPosition!,
                                    width: 40,
                                    height: 40,
                                    child: const Icon(Icons.my_location, color: Colors.blue, size: 36),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.all(16),
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
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Circuito Inteligente',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F2537)),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle, color: Color(0xFF0F2537), size: 32),
                                    onPressed: () => _showAddModal(),
                                  ),
                                ],
                              ),
                              const Divider(height: 10),
                              Expanded(
                                child: StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('deliveries')
                                      .where('userId', isEqualTo: _user?.uid)
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState == ConnectionState.waiting) {
                                      return const Center(child: CircularProgressIndicator());
                                    }

                                    final docs = snapshot.data?.docs ?? [];
                                    if (docs.isEmpty) {
                                      return const Center(
                                        child: Text(
                                          'Nenhum pacote na rota.\nEscaneie um código ou toque em +',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      );
                                    }

                                    final list = List.from(docs);
                                    if (_currentPosition != null) {
                                      list.sort((a, b) {
                                        final dataA = a.data() as Map<String, dynamic>;
                                        final dataB = b.data() as Map<String, dynamic>;
                                        final posA = LatLng(dataA['lat'] ?? 0.0, dataA['lng'] ?? 0.0);
                                        final posB = LatLng(dataB['lat'] ?? 0.0, dataB['lng'] ?? 0.0);
                                        final distA = _calculateDistance(_currentPosition!, posA);
                                        final distB = _calculateDistance(_currentPosition!, posB);
                                        return distA.compareTo(distB);
                                      });
                                    }

                                    return ListView.builder(
                                      itemCount: list.length,
                                      itemBuilder: (context, index) {
                                        final data = list[index].data() as Map<String, dynamic>;
                                        final docId = list[index].id;
                                        final isDone = data['status'] == 'concluido';

                                        return ListTile(
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
                                          subtitle: Text(data['complement'] ?? (isDone ? 'Concluído' : 'Pendente')),
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
                                                  FirebaseFirestore.instance
                                                      .collection('deliveries')
                                                      .doc(docId)
                                                      .update({'status': isDone ? 'pendente' : 'concluido'});
                                                },
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
