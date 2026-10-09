import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WebPortalScreen extends StatefulWidget {
  final Function(int) onTabChangeRequested;

  const WebPortalScreen({super.key, required this.onTabChangeRequested});

  @override
  State<WebPortalScreen> createState() => _WebPortalScreenState();
}

class _WebPortalScreenState extends State<WebPortalScreen> {
  final TextEditingController _usernameController = TextEditingController();
  bool _isLoggedIn = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedUser();
  }

  // 🌟 သိမ်းဆည်းထားသော Username ကို SharedPreferences မှ ဖတ်ယူခြင်း
  Future<void> _loadSavedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUser = prefs.getString('saved_username');
      if (savedUser != null && savedUser.trim().isNotEmpty) {
        _usernameController.text = savedUser;
        setState(() {
          _isLoggedIn = true;
        });
      }
    } catch (_) {} finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 🌟 Username ကို SharedPreferences တွင် သိမ်းဆည်းခြင်း
  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ ကျေးဇူးပြု၍ Username ထည့်ပါ။')),
      );
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_username', username);
      setState(() {
        _isLoggedIn = true;
      });
    } catch (_) {}
  }

  // 🌟 Logout ပြန်လုပ်လိုပါက Username ကို ရှင်းလင်းရန်
  Future<void> _handleLogout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_username');
      _usernameController.clear();
      setState(() {
        _isLoggedIn = false;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF101317),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
      );
    }

    if (!_isLoggedIn) {
      // 📱 အကယ်၍ Username မရှိသေးပါက (သို့မဟုတ် Logout လုပ်ထားပါက) Login မျက်နှာပြင်ပြမည်
      return Scaffold(
        backgroundColor: const Color(0xFF101317),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF16222F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2563EB)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lock_outline, color: Color(0xFF00E676), size: 24),
                      SizedBox(width: 8),
                      Text("DATA PLUS Login", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text("Username ထည့်သွင်းပါ:", style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _usernameController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF0D1117),
                      hintText: "Enter username...",
                      hintStyle: const TextStyle(color: Color(0xFF484F58), fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF30363D))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF00E676))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF238636),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _handleLogin,
                      child: const Text("ဝင်မည်", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 🚀 Login ဝင်ပြီးသားဖြစ်ပါက ပင်မ Portal မျက်နှာပြင်ပြမည်
    return Scaffold(
      backgroundColor: const Color(0xFF101317),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16222F),
        title: Text("ကြိုဆိုပါတယ် - ${_usernameController.text}", style: const TextStyle(color: Colors.white, fontSize: 14)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFF85149), size: 20),
            onPressed: _handleLogout,
            tooltip: "Logout",
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, color: Color(0xFF00E676), size: 64),
            const SizedBox(height: 16),
            Text("User: ${_usernameController.text}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text("အပ္ပလီကေးရှင်း အပ်ဒိတ်လုပ်သည့်အခါ Username ထပ်ထည့်ရန် မလိုတော့ပါ။", style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
