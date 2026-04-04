import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../domain/geyser/entities/geyser_config.dart';

/// Reads and writes geyser config fields on the Firestore `users/{uid}`
/// document. Uses `merge: true` so profile fields are never overwritten.
class GeyserConfigRepository {
  GeyserConfigRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  })  : _auth = auth,
        _firestore = firestore;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _userDoc() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No authenticated user');
    return _firestore.collection('users').doc(uid);
  }

  Future<GeyserConfig> getConfig() async {
    final snap = await _userDoc().get();
    return GeyserConfig.fromMap(snap.data());
  }

  /// Streams config changes so edits from another device sync live.
  Stream<GeyserConfig> watchConfig() {
    return _userDoc().snapshots().map(
          (snap) => GeyserConfig.fromMap(snap.data()),
        );
  }

  Future<void> saveConfig(GeyserConfig config) async {
    await _userDoc().set(config.toMap(), SetOptions(merge: true));
  }
}
