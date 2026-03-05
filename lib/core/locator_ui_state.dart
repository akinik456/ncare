import 'package:flutter/foundation.dart';

enum LocatorPhase { ready, processing, sent }

class LocatorUiState {
  LocatorUiState._();
  static final instance = LocatorUiState._();

  final ValueNotifier<LocatorPhase> phase = ValueNotifier(LocatorPhase.ready);
  final ValueNotifier<String?> lastRequestId = ValueNotifier<String?>(null);

  void onRequestReceived(String requestId) {
    lastRequestId.value = requestId;
    phase.value = LocatorPhase.processing;
  }

  void onSentOk() {
    phase.value = LocatorPhase.sent;
    // 2.5s sonra tekrar READY
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (phase.value == LocatorPhase.sent) phase.value = LocatorPhase.ready;
    });
  }

  void reset() {
    phase.value = LocatorPhase.ready;
  }
}