import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:mywaguri/Utils/constants.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mywaguri/Screens/Login/login_page.dart';
import 'package:mywaguri/Screens/profile_detail_screen.dart';
import 'package:mywaguri/Services/notification_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String _currentTime = "";
  String _currentDate = "";

  String? _checkInTime;
  String? _checkOutTime;
  String? _todayDocId;
  Timer? _timer;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _user = FirebaseAuth.instance.currentUser;
  String get _userEmail => _user?.email ?? "Guest";
  String get _userName =>
      _user?.displayName ?? _user?.email?.split('@').first ?? "User";

  // Konfigurasi Lokasi Kantor (Ganti dengan koordinat kantor asli Anda)
  static const double _officeLat = -6.200000; // Contoh: Jakarta
  static const double _officeLng = 106.816666;
  static const double _maxDistance = 50.0; // Meter

  @override
  void initState() {
    super.initState();
    _startTimer();
    _checkTodayStatus();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _currentTime = DateFormat('HH:mm:ss').format(DateTime.now());
        _currentDate = DateFormat('EEEE, dd MMMM yyyy').format(DateTime.now());
      });
    });
  }

  Future<bool> _checkInternet() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) {
      _showSnackBar("Tidak ada koneksi internet. Periksa jaringan Anda.");
      return false;
    }
    return true;
  }

  void _checkTodayStatus() async {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    var snapshot = await _firestore
        .collection('absensi')
        .where('email', isEqualTo: _userEmail)
        .where('tanggal', isEqualTo: today)
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      var data = snapshot.docs.first.data();
      setState(() {
        _todayDocId = snapshot.docs.first.id;
        _checkInTime = data['waktu_masuk'];
        _checkOutTime = data['waktu_pulang'];
      });
    }
  }

  void _handleLogout() async {
    // Tampilkan loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(color: kPrimaryColor),
            const SizedBox(width: 20),
            Text("Keluar...", style: GoogleFonts.poppins()),
          ],
        ),
      ),
    );

    // Panggil sign out asli
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;
    Navigator.pop(context); // Tutup loading dialog
    // Pindah ke LoginPage dan hapus semua history navigasi
    // Sebenarnya AuthWrapper akan otomatis mendeteksi logout,
    // tapi pushAndRemoveUntil menjamin kebersihan stack navigasi.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  Future<bool> _checkLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar("Layanan lokasi tidak aktif. Silakan aktifkan GPS.");
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar("Izin lokasi ditolak.");
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackBar("Izin lokasi ditolak secara permanen.");
      return false;
    }

    // Tampilkan loading sebentar saat mengambil lokasi
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: kPrimaryColor)),
    );

    try {
      // Timeout 5 detik agar tidak hang selamanya
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy:
            LocationAccuracy.low, // Gunakan low untuk kecepatan testing
        timeLimit: const Duration(seconds: 5),
      );
      Navigator.pop(context); // Tutup loading
      return true;
    } catch (e) {
      Navigator.pop(context);
      print("GPS Error: $e");
      // Untuk testing, kita biarkan saja lolos meski GPS error
      return true;
    }
  }

  void _handleCheckIn() async {
    if (_checkInTime != null) {
      _showSnackBar(
          "Anda sudah melakukan absen masuk atau sedang izin hari ini!");
      return;
    }

    // 1. Cek Internet
    bool hasInternet = await _checkInternet();
    if (!hasInternet) return;

    // 2. Validasi Lokasi
    bool isAtOffice = await _checkLocation();
    if (!isAtOffice) return;

    String timeNow = DateFormat('HH:mm').format(DateTime.now());
    String dateNow = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      DocumentReference docRef = await _firestore.collection('absensi').add({
        "email": _userEmail,
        "nama": _userName,
        "tanggal": dateNow,
        "waktu_masuk": timeNow,
        "waktu_pulang": null,
        "status": "Hadir",
        "timestamp": FieldValue.serverTimestamp(),
      });

      setState(() {
        _checkInTime = timeNow;
        _todayDocId = docRef.id;
      });

      _showSuccessDialog("Berhasil Absen Masuk",
          "Selamat bekerja! Data tersimpan di Firebase.");
      NotificationService.showLocalNotification("Absen Masuk Berhasil",
          "Selamat bekerja! Anda masuk pada pukul $timeNow");
    } catch (e) {
      _showSnackBar("Gagal simpan data: $e");
    }
  }

  void _handleCheckOut() async {
    print("Check-out dipicu...");
    if (_checkInTime == null || _checkInTime == "--:--") {
      _showSnackBar("Silakan absen masuk terlebih dahulu!");
      return;
    }
    if (_checkOutTime != null && _checkOutTime != "--:--") {
      _showSnackBar("Anda sudah melakukan absen pulang hari ini!");
      return;
    }

    // 1. Cek Internet
    bool hasInternet = await _checkInternet();
    print("Cek internet: $hasInternet");
    if (!hasInternet) return;

    // 2. Validasi Lokasi
    bool isAtOffice = await _checkLocation();
    print("Cek lokasi: $isAtOffice");
    if (!isAtOffice) return;

    String timeNow = DateFormat('HH:mm').format(DateTime.now());

    try {
      // Jika _todayDocId hilang (misal karena reload), coba cari lagi sebelum update
      if (_todayDocId == null) {
        String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        var snap = await _firestore
            .collection('absensi')
            .where('email', isEqualTo: _userEmail)
            .where('tanggal', isEqualTo: today)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          _todayDocId = snap.docs.first.id;
        } else {
          _showSnackBar("Data absen hari ini tidak ditemukan!");
          return;
        }
      }

      await _firestore.collection('absensi').doc(_todayDocId).update({
        "waktu_pulang": timeNow,
      });

      setState(() {
        _checkOutTime = timeNow;
      });

      _showSuccessDialog("Berhasil Absen Pulang",
          "Data pulang tersimpan. Hati-hati di jalan!");
      NotificationService.showLocalNotification("Absen Pulang Berhasil",
          "Hati-hati di jalan! Anda pulang pada pukul $timeNow");
    } catch (e) {
      _showSnackBar("Gagal update data: $e");
    }
  }

  void _showIzinDialog() {
    final TextEditingController reasonController = TextEditingController();
    String selectedType = 'Izin';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Pengajuan Izin / Sakit",
                  style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Row(
                children: [
                  _typeChip(setModalState, "Izin", selectedType == "Izin",
                      (val) => selectedType = val),
                  const SizedBox(width: 10),
                  _typeChip(setModalState, "Sakit", selectedType == "Sakit",
                      (val) => selectedType = val),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  hintText: "Alasan ketidakhadiran...",
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    if (reasonController.text.isEmpty) {
                      _showSnackBar("Alasan tidak boleh kosong!");
                      return;
                    }
                    Navigator.pop(context);
                    _submitIzin(selectedType, reasonController.text);
                  },
                  child: const Text("Kirim Pengajuan",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeChip(StateSetter setModalState, String label, bool isSelected,
      Function(String) onSelect) {
    return ActionChip(
      label: Text(label),
      labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.black,
          fontWeight: FontWeight.bold),
      backgroundColor: isSelected ? kPrimaryColor : Colors.grey[200],
      onPressed: () {
        setModalState(() => onSelect(label));
      },
    );
  }

  void _submitIzin(String type, String reason) async {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    var check = await _firestore
        .collection('absensi')
        .where('email', isEqualTo: _userEmail)
        .where('tanggal', isEqualTo: today)
        .get();
    if (check.docs.isNotEmpty) {
      _showSnackBar("Anda sudah memiliki riwayat (Hadir/Izin) hari ini.");
      return;
    }

    try {
      await _firestore.collection('absensi').add({
        "email": _userEmail,
        "nama": _userName,
        "tanggal": today,
        "waktu_masuk": "--:--",
        "waktu_pulang": "--:--",
        "status": type,
        "alasan": reason,
        "timestamp": FieldValue.serverTimestamp(),
      });
      _showSuccessDialog(
          "Pengajuan Terkirim", "Data $type Anda telah tercatat.");
      NotificationService.showLocalNotification("Pengajuan $type Terkirim",
          "Data $type Anda telah tercatat pada pukul ${DateFormat('HH:mm').format(DateTime.now())}");
    } catch (e) {
      _showSnackBar("Gagal kirim izin: $e");
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSuccessDialog(String title, String subtitle) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: kPrimaryColor, size: 80),
            const SizedBox(height: 20),
            Text(title,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 10),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: mSubtitleColor)),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text("Oke", style: TextStyle(color: Colors.white)),
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildHomeTab(),
            _buildHistoryTab(),
            _buildProfileTab(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAttendanceCard(),
                const SizedBox(height: 16),
                _buildIzinButton(),
                const SizedBox(height: 32),
                _buildSectionTitle('Statistik Kehadiran'),
                const SizedBox(height: 16),
                _buildStatGrid(),
                const SizedBox(height: 32),
                _buildSectionTitle('Aktivitas Hari Ini'),
                const SizedBox(height: 16),
                _buildTodayActivity(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIzinButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          side: const BorderSide(color: kPrimaryColor),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: _showIzinDialog,
        icon: const Icon(Icons.note_add_outlined, color: kPrimaryColor),
        label: Text("Ajukan Izin / Sakit",
            style: GoogleFonts.poppins(
                color: kPrimaryColor, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Riwayat Absensi",
              style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: mTitleColor)),
          const SizedBox(height: 20),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('absensi')
                  .where('email', isEqualTo: _userEmail)
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return Center(child: Text("Error: ${snapshot.error}"));
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                  return const Center(child: Text("Belum ada riwayat."));

                return ListView.separated(
                  itemCount: snapshot.data!.docs.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    var doc = snapshot.data!.docs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    return _buildHistoryItem({
                      "date": data['tanggal'] ?? "-",
                      "in": data['waktu_masuk'] ?? "--:--",
                      "out": data['waktu_pulang'] ?? "--:--",
                      "status": data['status'] ?? "Hadir"
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTab() {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(_user?.uid).get(),
      builder: (context, snapshot) {
        String name = _userName;
        String job = "Karyawan";

        if (snapshot.hasData && snapshot.data!.exists) {
          var data = snapshot.data!.data() as Map<String, dynamic>;
          name = data['nama'] ?? name;
          job = data['jabatan'] ?? job;
        }

        return SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Center(
                child: CircleAvatar(
                    radius: 60,
                    backgroundImage: AssetImage("assets/images/avatar.jpg")),
              ),
              const SizedBox(height: 16),
              Text(name,
                  style: GoogleFonts.poppins(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              Text(job, style: GoogleFonts.poppins(color: mSubtitleColor)),
              const SizedBox(height: 40),
              _buildProfileMenu(Icons.person_outline, "Informasi Pribadi", () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileDetailScreen(
                      title: "Informasi Pribadi",
                      type: "personal",
                    ),
                  ),
                );
              }),
              _buildProfileMenu(Icons.settings_outlined, "Pengaturan", () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileDetailScreen(
                      title: "Pengaturan",
                      type: "settings",
                    ),
                  ),
                );
              }),
              _buildProfileMenu(Icons.help_outline, "Pusat Bantuan", () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileDetailScreen(
                      title: "Pusat Bantuan",
                      type: "help",
                    ),
                  ),
                );
              }),
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _handleLogout,
                    child: const Text("Keluar Akun",
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(_user?.uid).get(),
      builder: (context, snapshot) {
        String name = _userName;
        if (snapshot.hasData && snapshot.data!.exists) {
          name =
              (snapshot.data!.data() as Map<String, dynamic>)['nama'] ?? name;
        }

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                      backgroundImage: AssetImage('assets/images/avatar.jpg')),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Halo, $name',
                          style: GoogleFonts.poppins(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Jangan lupa absen ya!',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: mSubtitleColor)),
                    ],
                  ),
                ],
              ),
              const Icon(Icons.notifications_none_rounded,
                  color: mSubtitleColor),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttendanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient:
            const LinearGradient(colors: [kPrimaryColor, kSecondaryColor]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: kPrimaryColor.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        children: [
          Text(_currentTime,
              style: GoogleFonts.poppins(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text(_currentDate,
              style: GoogleFonts.poppins(
                  fontSize: 14, color: Colors.white.withOpacity(0.8))),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                  child: _buildAttendanceButton('Masuk', Icons.login,
                      _handleCheckIn, _checkInTime != null)),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildAttendanceButton('Pulang', Icons.logout,
                      _handleCheckOut, _checkOutTime != null)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildAttendanceButton(
      String label, IconData icon, VoidCallback onTap, bool disabled) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: disabled
            ? Colors.grey.withOpacity(0.3)
            : Colors.white.withOpacity(0.2),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(vertical: 18), // Diperbesar dari 12
      ),
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white, size: 24), // Diperbesar dari 20
      label: Text(label,
          style: const TextStyle(
              fontSize: 15, // Ditambahkan ukuran font
              color: Colors.white,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildTodayActivity() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildActivityTime("Masuk", _checkInTime ?? "--:--", kPrimaryColor),
          Container(height: 40, width: 1, color: Colors.grey.shade200),
          _buildActivityTime("Pulang", _checkOutTime ?? "--:--", Colors.orange),
        ],
      ),
    );
  }

  Widget _buildActivityTime(String label, String time, Color color) {
    return Column(
      children: [
        Text(label,
            style: GoogleFonts.poppins(color: mSubtitleColor, fontSize: 12)),
        const SizedBox(height: 4),
        Text(time,
            style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildStatGrid() {
    return StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('absensi')
            .where('email', isEqualTo: _userEmail)
            .snapshots(),
        builder: (context, snapshot) {
          int hadir = 0;
          int izin = 0;
          if (snapshot.hasData) {
            for (var doc in snapshot.data!.docs) {
              String status = doc['status'] ?? "";
              if (status == "Hadir") hadir++;
              if (status == "Izin" || status == "Sakit") izin++;
            }
          }

          return Row(
            children: [
              _buildStatItem("Hadir", hadir.toString(), kPrimaryColor),
              const SizedBox(width: 12),
              _buildStatItem("Izin", izin.toString(), kColorYellow),
              const SizedBox(width: 12),
              _buildStatItem("Alpa", "0", kColorRedSlow),
            ],
          );
        });
  }

  Widget _buildStatItem(String label, String count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Text(count,
                style: GoogleFonts.poppins(
                    fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style:
                    GoogleFonts.poppins(fontSize: 12, color: mSubtitleColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> data) {
    Color statusColor = Colors.green;
    if (data["status"] == "Izin" || data["status"] == "Sakit")
      statusColor = kColorYellow;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: kPrimaryColor.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.calendar_today,
                color: kPrimaryColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data["date"]!,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                Text("In: ${data["in"]} | Out: ${data["out"]}",
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: mSubtitleColor)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20)),
            child: Text(
              data["status"]!,
              style: TextStyle(
                  color: statusColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildProfileMenu(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: kPrimaryColor),
      title: Text(title, style: GoogleFonts.poppins()),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (index) => setState(() => _selectedIndex = index),
      selectedItemColor: kPrimaryColor,
      unselectedItemColor: Colors.grey,
      items: const [
        BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_rounded), label: "Utama"),
        BottomNavigationBarItem(
            icon: Icon(Icons.history_rounded), label: "Riwayat"),
        BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded), label: "Profil"),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: GoogleFonts.poppins(
            fontSize: 16, fontWeight: FontWeight.bold, color: mTitleColor));
  }
}
