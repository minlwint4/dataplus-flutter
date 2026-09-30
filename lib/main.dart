import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/web_portal_screen.dart';
import 'screens/downloader_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await [Permission.storage].request();
  runApp(const DataPlusApp());
}

class DataPlusApp extends StatelessWidget {
  const DataPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DATA PLUS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          WebPortalScreen(onTabChangeRequested: (index) => setState(() => _currentIndex = index)),
          const DownloaderScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        backgroundColor: const Color(0xFF1E232B),
        selectedItemColor: const Color(0xFF00E676),
        unselectedItemColor: const Color(0xFF8B949E),
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.movie_creation_outlined), label: 'Web Portal'),
          BottomNavigationBarItem(icon: Icon(Icons.download_rounded), label: 'Downloader'),
        ],
      ),
    );
  }
}
