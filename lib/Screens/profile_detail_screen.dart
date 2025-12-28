import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mywaguri/Utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mywaguri/main.dart';

class ProfileDetailScreen extends StatefulWidget {
  final String title;
  final String type; // 'personal', 'settings', 'help'

  const ProfileDetailScreen({
    super.key,
    required this.title,
    required this.type,
  });

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  bool _isNotificationEnabled = true;
  bool _isDarkModeEnabled = false;
  bool _isBiometricEnabled = true;
  String _selectedLanguage = "Indonesia";

  @override
  void initState() {
    super.initState();
    if (widget.type == 'settings') {
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isNotificationEnabled = prefs.getBool('notif_enabled') ?? true;
      _isDarkModeEnabled = prefs.getBool('dark_mode_enabled') ?? false;
      _isBiometricEnabled = prefs.getBool('biometric_enabled') ?? true;
      _selectedLanguage = prefs.getString('language') ?? "Indonesia";
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text(widget.title,
            style: GoogleFonts.poppins(
                color: mTitleColor, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: mTitleColor),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (widget.type) {
      case 'personal':
        return _buildPersonalContent();
      case 'settings':
        return _buildSettingsContent();
      case 'help':
        return _buildHelpContent();
      default:
        return const Center(child: Text("Halaman tidak ditemukan"));
    }
  }

  Widget _buildPersonalContent() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Silakan login kembali"));

    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: kPrimaryColor));
        }

        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          // Fallback jika data di Firestore belum ada (user lama/error)
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _buildInfoItem(Icons.badge_outlined, "Nama Lengkap",
                    user.displayName ?? "User"),
                _buildInfoItem(
                    Icons.email_outlined, "Email", user.email ?? "-"),
                _buildInfoItem(
                    Icons.phone_android_outlined, "Nomor Telepon", "-"),
                _buildInfoItem(Icons.work_outline, "Jabatan", "Karyawan"),
                _buildInfoItem(Icons.location_on, "Alamat", "-"),
              ],
            ),
          );
        }

        var userData = snapshot.data!.data() as Map<String, dynamic>;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              _buildInfoItem(Icons.badge_outlined, "Nama Lengkap",
                  userData['nama'] ?? user.displayName ?? "User"),
              _buildInfoItem(Icons.email_outlined, "Email",
                  userData['email'] ?? user.email ?? "-"),
              _buildInfoItem(Icons.phone_android_outlined, "Nomor Telepon",
                  userData['phone'] ?? "-"),
              _buildInfoItem(Icons.work_outline, "Jabatan",
                  userData['jabatan'] ?? "Karyawan"),
              _buildInfoItem(
                  Icons.location_on, "Alamat", userData['alamat'] ?? "-"),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingsContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSettingToggle(
          Icons.notifications_active_outlined,
          "Notifikasi App",
          _isNotificationEnabled,
          (val) {
            setState(() => _isNotificationEnabled = val);
            _saveSetting('notif_enabled', val);
          },
        ),
        _buildSettingToggle(
          Icons.dark_mode_outlined,
          "Mode Gelap",
          _isDarkModeEnabled,
          (val) {
            setState(() => _isDarkModeEnabled = val);
            _saveSetting('dark_mode_enabled', val);
            // Update global theme
            themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
          },
        ),
        _buildSettingToggle(
          Icons.fingerprint,
          "Biometrik Login",
          _isBiometricEnabled,
          (val) {
            setState(() => _isBiometricEnabled = val);
            _saveSetting('biometric_enabled', val);
          },
        ),
        const Divider(),
        _buildSettingTile(Icons.language, "Bahasa", _selectedLanguage, () {
          _showLanguagePicker();
        }),
        _buildSettingTile(
            Icons.lock_outline, "Ganti Password", "Klik untuk mengubah", () {
          _showChangePasswordDialog();
        }),
        _buildSettingTile(Icons.info_outline, "Versi Aplikasi", "1.0.0", null),
      ],
    );
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Pilih Bahasa",
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _languageOption("Indonesia"),
            _languageOption("English"),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _languageOption(String lang) {
    return ListTile(
      title: Text(lang, style: GoogleFonts.poppins()),
      trailing: _selectedLanguage == lang
          ? const Icon(Icons.check_circle, color: kPrimaryColor)
          : null,
      onTap: () {
        setState(() => _selectedLanguage = lang);
        _saveSetting('language', lang);
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Bahasa diubah ke $lang")));
      },
    );
  }

  void _showChangePasswordDialog() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Ganti Password",
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
          "Kami akan mengirimkan link pengaturan ulang kata sandi ke email Anda: \n\n${user.email}",
          style: GoogleFonts.poppins(fontSize: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
            onPressed: () async {
              try {
                await FirebaseAuth.instance
                    .sendPasswordResetEmail(email: user.email!);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            "Link reset password telah dikirim ke email!")),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Gagal mengirim email: $e")),
                  );
                }
              }
            },
            child: const Text("Kirim Email",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Ada yang bisa kami bantu?",
              style: GoogleFonts.poppins(
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text("Hubungi kami jika Anda mengalami kendala pada aplikasi.",
              style: GoogleFonts.poppins(color: mSubtitleColor)),
          const SizedBox(height: 30),
          _buildContactCard(Icons.chat_bubble_outline, "Chat Hubungi Kami",
              "WhatsApp (Fast Response)"),
          _buildContactCard(
              Icons.email_outlined, "Email Support", "support@mywaguri.com"),
          _buildContactCard(Icons.public, "Website Resmi", "www.mywaguri.com"),
          const SizedBox(height: 40),
          Text("FAQ",
              style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildFaqItem("Bagaimana cara absen masuk?",
              "Masuk ke menu utama dan klik tombol 'Masuk'."),
          _buildFaqItem("Mengapa lokasi saya tidak terbaca?",
              "Pastikan GPS Anda aktif dan berikan izin lokasi."),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: kPrimaryColor),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      GoogleFonts.poppins(fontSize: 12, color: mSubtitleColor)),
              Text(value,
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSettingToggle(
      IconData icon, String title, bool value, Function(bool) onChanged) {
    return ListTile(
      leading: Icon(icon, color: kPrimaryColor),
      title: Text(title, style: GoogleFonts.poppins()),
      trailing: Switch(
          value: value,
          onChanged: (v) => onChanged(v),
          activeColor: kPrimaryColor),
    );
  }

  Widget _buildSettingTile(
      IconData icon, String title, String subtitle, VoidCallback? onTap) {
    return ListTile(
      leading: Icon(icon, color: kPrimaryColor),
      title: Text(title, style: GoogleFonts.poppins()),
      subtitle: subtitle.isNotEmpty
          ? Text(subtitle, style: GoogleFonts.poppins(fontSize: 12))
          : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildContactCard(IconData icon, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
          ]),
      child: Row(
        children: [
          CircleAvatar(
              backgroundColor: kPrimaryColor.withOpacity(0.1),
              child: Icon(icon, color: kPrimaryColor)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                Text(subtitle,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: mSubtitleColor)),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 14, color: mSubtitleColor),
        ],
      ),
    );
  }

  Widget _buildFaqItem(String question, String answer) {
    return ExpansionTile(
      title: Text(question,
          style:
              GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child:
              Text(answer, style: GoogleFonts.poppins(color: mSubtitleColor)),
        )
      ],
    );
  }
}
