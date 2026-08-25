import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Tratamento seguro para nunca travar na tela de splash
  try {
    await Firebase.initializeApp().timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        debugPrint("Timeout na inicializacao do Firebase");
        return Firebase.app();
      },
    );
  } catch (e) {
    debugPrint("Aviso: Firebase nao inicializado: $e");
  }

  runApp(const AppEntregas());
}

class AppEntregas extends StatelessWidget {
  const AppEntregas({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Entregas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Map<String, dynamic>> _entregas = [
    {
      'cliente': 'Mercado Central',
      'endereco': 'Av. Principal, 1200',
      'valor': 'R\$ 25,00',
      'status': 'Pendente',
      'distancia': '2.4 km',
    },
    {
      'cliente': 'Auto Peças Express',
      'endereco': 'Rua dos Ferroviários, 450',
      'valor': 'R\$ 18,50',
      'status': 'Em rota',
      'distancia': '4.1 km',
    },
    {
      'cliente': 'Lanchonete 24h',
      'endereco': 'Rua das Flores, 88',
      'valor': 'R\$ 12,00',
      'status': 'Entregue',
      'distancia': '1.2 km',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Painel de Entregas',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Lista de entregas atualizada!'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: _selectedIndex == 0 ? _buildEntregasTab() : _buildPerfilTab(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.two_wheeler),
            label: 'Entregas',
          ),
          NavigationDestination(
            icon: Icon(Icons.person),
            label: 'Meu Perfil',
          ),
        ],
      ),
    );
  }

  Widget _buildEntregasTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _entregas.length,
      itemBuilder: (context, index) {
        final entrega = _entregas[index];
        final bool isEntregue = entrega['status'] == 'Entregue';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      entrega['cliente'],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      entrega['valor'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.greenAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        entrega['endereco'],
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Chip(
                      label: Text(entrega['status']),
                      backgroundColor: isEntregue
                          ? Colors.green.withOpacity(0.2)
                          : Colors.orange.withOpacity(0.2),
                      side: BorderSide.none,
                    ),
                    Row(
                      children: [
                        const Icon(Icons.navigation, size: 16, color: Colors.cyanAccent),
                        const SizedBox(width: 4),
                        Text(
                          entrega['distancia'],
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPerfilTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          CircleAvatar(
            radius: 45,
            backgroundColor: Colors.deepOrange,
            child: Icon(Icons.person, size: 50, color: Colors.white),
          ),
          SizedBox(height: 16),
          Text(
            'Entregador Conectado',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Status: Disponível para corridas',
            style: TextStyle(color: Colors.greenAccent),
          ),
        ],
      ),
    );
  }
}
