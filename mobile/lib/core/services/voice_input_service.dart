import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// On-device speech-to-text for push-to-talk voice input (AI chat, and any
/// future text field that wants it) — no API key, no network round-trip,
/// works offline on devices with Android's built-in speech recognizer.
/// Mirrors the app's existing permission_handler request pattern (see
/// ReceiptPrinterService.requestPermission).
class VoiceInputService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      debugLogging: false,
      onError: (_) {},
      onStatus: (_) {},
    );
    return _initialized;
  }

  bool get isListening => _speech.isListening;

  /// Starts listening and streams partial + final transcriptions via
  /// [onResult]. Stops automatically after a pause in speech (handled by
  /// the platform's speech recognizer) or when [stop] is called.
  Future<bool> startListening({
    required void Function(String text, bool isFinal) onResult,
    String localeId = 'en_US',
  }) async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return false;

    final ready = await _ensureInitialized();
    if (!ready) return false;

    await _speech.listen(
      onResult: (result) {
        onResult(result.recognizedWords, result.finalResult);
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        localeId: localeId,
      ),
    );
    return true;
  }

  Future<void> stop() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  Future<void> cancel() async {
    if (_speech.isListening) {
      await _speech.cancel();
    }
  }
}
