import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

final db = FirebaseFirestore.instance;
String today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MaterialApp(
    title: 'Queue Manager',
    theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
    home: StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (_, s) => s.data == null ? const Login() : const Home(),
    ),
  ));
}

// ---------- LOGIN (mobile + OTP) ----------
class Login extends StatefulWidget {
  const Login({super.key});
  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final phone = TextEditingController(), otp = TextEditingController();
  String? vid;
  bool busy = false;

  void msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> send() async {
    setState(() => busy = true);
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: '+91${phone.text.trim()}',
      verificationCompleted: (c) => FirebaseAuth.instance.signInWithCredential(c),
      verificationFailed: (e) {
        msg(e.message ?? 'Failed');
        setState(() => busy = false);
      },
      codeSent: (id, _) => setState(() {
        vid = id;
        busy = false;
      }),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> verify() async {
    try {
      await FirebaseAuth.instance.signInWithCredential(
          PhoneAuthProvider.credential(verificationId: vid!, smsCode: otp.text.trim()));
    } catch (_) {
      msg('Wrong OTP');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.restaurant, size: 64, color: Colors.deepOrange),
            const Text('Queue Manager', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            if (vid == null) ...[
              TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  decoration: const InputDecoration(
                      labelText: 'Restaurant mobile number', prefixText: '+91 ', border: OutlineInputBorder())),
              FilledButton(onPressed: busy ? null : send, child: const Text('Send OTP')),
            ] else ...[
              TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(labelText: 'Enter OTP', border: OutlineInputBorder())),
              FilledButton(onPressed: verify, child: const Text('Verify & Login')),
            ],
          ]),
        ),
      );
}

// ---------- HOME ----------
class Home extends StatelessWidget {
  const Home({super.key});
  String get uid => FirebaseAuth.instance.currentUser!.uid;
  DocumentReference<Map<String, dynamic>> get rref => db.collection('restaurants').doc(uid);

  Future<void> setName(BuildContext c) async {
    final t = TextEditingController();
    await showDialog(
        context: c,
        builder: (_) => AlertDialog(
              title: const Text('Restaurant name'),
              content: TextField(controller: t),
              actions: [
                TextButton(
                    onPressed: () {
                      rref.set({'name': t.text.trim()}, SetOptions(merge: true));
                      Navigator.pop(c);
                    },
                    child: const Text('Save'))
              ],
            ));
  }

  Future<void> addGuest(BuildContext c, {QueryDocumentSnapshot<Map<String, dynamic>>? edit}) async {
    final d = edit?.data() ?? {};
    final name = TextEditingController(text: d['name']);
    final ph = TextEditingController(text: d['phone']);
    final note = TextEditingController(text: d['note']);
    int pax = d['pax'] ?? 2;
    await showDialog(
        context: c,
        builder: (_) => StatefulBuilder(
            builder: (_, set) => AlertDialog(
                  title: Text(edit == null ? 'Add to waiting list' : 'Edit entry'),
                  content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(controller: name, decoration: const InputDecoration(labelText: 'Customer name')),
                      TextField(
                          controller: ph,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91 ')),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('People'),
                        IconButton(
                            onPressed: () => set(() => pax = max(1, pax - 1)), icon: const Icon(Icons.remove_circle)),
                        Text('$pax', style: const TextStyle(fontSize: 22)),
                        IconButton(onPressed: () => set(() => pax++), icon: const Icon(Icons.add_circle)),
                      ]),
                      TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
                    ]),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () async {
                          final data = {'name': name.text.trim(), 'phone': ph.text.trim(), 'pax': pax, 'note': note.text.trim()};
                          if (edit != null) {
                            await edit.reference.update(data);
                          } else {
                            // atomic daily token, safe for several receptionists at once
                            await db.runTransaction((t) async {
                              final s = await t.get(rref);
                              final m = s.data() ?? {};
                              final n = (m['day'] == today() ? (m['counter'] ?? 0) as int : 0) + 1;
                              t.set(rref, {'day': today(), 'counter': n}, SetOptions(merge: true));
                              final id = List.generate(16, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
                              t.set(rref.collection('queue').doc(id), {
                                ...data,
                                'token': n,
                                'day': today(),
                                'status': 'waiting',
                                'extraMin': 0,
                                'createdAt': FieldValue.serverTimestamp(),
                              });
                            });
                          }
                          if (c.mounted) Navigator.pop(c);
                        },
                        child: const Text('Save'))
                  ],
                )));
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Waiting List'),
            actions: [
              IconButton(icon: const Icon(Icons.store), onPressed: () => setName(context)),
              IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut()),
            ],
            bottom: const TabBar(tabs: [Tab(text: 'Active'), Tab(text: 'Done today')]),
          ),
          floatingActionButton: FloatingActionButton.extended(
              onPressed: () => addGuest(context), icon: const Icon(Icons.person_add), label: const Text('Add')),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: rref.collection('queue').where('day', isEqualTo: today()).snapshots(),
            builder: (_, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              final all = s.data!.docs.toList()..sort((a, b) => (a['token'] as int).compareTo(b['token'] as int));
              final active = all.where((d) => d['status'] == 'waiting' || d['status'] == 'notified').toList();
              final done = all.where((d) => !active.contains(d)).toList();
              return TabBarView(children: [list(context, active, true), list(context, done, false)]);
            },
          ),
        ),
      );

  Widget list(BuildContext c, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, bool actions) => docs.isEmpty
      ? const Center(child: Text('Nothing here'))
      : ListView(
          padding: const EdgeInsets.only(bottom: 90),
          children: docs.map((d) {
            final m = d.data();
            final ts = (m['createdAt'] as Timestamp?)?.toDate();
            final waited = ts == null ? 0 : DateTime.now().difference(ts).inMinutes;
            Widget chip(IconData i, String l, Map<String, dynamic> u) =>
                ActionChip(avatar: Icon(i, size: 18), label: Text(l), onPressed: () => d.reference.update(u));
            return Card(
              margin: const EdgeInsets.all(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(radius: 24, child: Text('T${m['token']}')),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('${m['pax']} people • ${m['phone']} • waited $waited min'),
                      if ((m['note'] ?? '') != '') Text('Note: ${m['note']}'),
                    ])),
                    Chip(label: Text(m['status'])),
                  ]),
                  if (actions)
                    Wrap(spacing: 6, children: [
                      chip(Icons.notifications_active, 'Call', {'status': 'notified'}),
                      chip(Icons.event_seat, 'Seated', {'status': 'seated'}),
                      chip(Icons.person_off, 'Not arrived', {'status': 'noshow'}),
                      chip(Icons.cancel, 'Cancel', {'status': 'cancelled'}),
                      chip(Icons.more_time, '+10 min', {'extraMin': FieldValue.increment(10)}),
                      ActionChip(avatar: const Icon(Icons.edit, size: 18), label: const Text('Edit'), onPressed: () => addGuest(c, edit: d)),
                    ])
                  else
                    TextButton(onPressed: () => d.reference.update({'status': 'waiting'}), child: const Text('Restore to queue')),
                ]),
              ),
            );
          }).toList(),
        );
}
