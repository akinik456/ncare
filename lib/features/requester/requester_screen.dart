import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RequesterScreen extends StatefulWidget {
  const RequesterScreen({super.key});

  @override
  State<RequesterScreen> createState() => _RequesterScreenState();
}

class _RequesterScreenState extends State<RequesterScreen> {
  String? _lastRequestId;

  Future<void> _sendRequest() async {
    final doc = await FirebaseFirestore.instance.collection('requests').add({
      'type': 'rl',
      'ts': FieldValue.serverTimestamp(),
    });

    setState(() => _lastRequestId = doc.id);
  }

  @override
  Widget build(BuildContext context) {
    final requestId = _lastRequestId;

    return Scaffold(
      appBar: AppBar(title: const Text('NCare Requester')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _sendRequest,
                child: const Text('Request Location'),
              ),
              const SizedBox(height: 16),
              Text('requestId: ${requestId ?? "-"}'),

              const SizedBox(height: 24),

              if (requestId != null)
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('responses')
                      .doc(requestId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Text('Waiting response...');
                    final data = snapshot.data!.data();
                    if (data == null) return const Text('Waiting response...');

                    return Text(
                      'status: ${data['status']}\n'
                      'lat: ${data['lat']}\n'
                      'lng: ${data['lng']}\n'
                      'acc: ${data['acc']}\n'
                      'ts: ${data['ts']}',
                      textAlign: TextAlign.center,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}