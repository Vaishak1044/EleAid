import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

const _modelAsset = 'assets/efficientnet_lite0_mobile_model.tflite';
const _labelsAsset = 'assets/efficientnet_lite0_mobile_labels.txt';
const _sampleRate = 48000;
const _windowSeconds = 3;
const _imageSize = 224;
const _fftSize = 2048;
const _hopSize = 512;
const _melCount = 224;
const _directSmsEnabled = bool.fromEnvironment('ELEAID_DIRECT_SMS', defaultValue: false);

void main() => runApp(const EleAidApp());

class EleAidApp extends StatelessWidget {
  const EleAidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EleAid Independent Detector',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const IndependentDetectorPage(),
    );
  }
}

class IndependentDetectorPage extends StatefulWidget {
  const IndependentDetectorPage({super.key});

  @override
  State<IndependentDetectorPage> createState() => _IndependentDetectorPageState();
}

class _IndependentDetectorPageState extends State<IndependentDetectorPage> {
  static const _native = MethodChannel('eleaid/native');

  final _recorder = AudioRecorder();
  final _labelController = TextEditingController(text: 'Elephant');
  final _recordLabelController = TextEditingController(text: 'Elephant');
  final _sampleDurationController = TextEditingController(text: '10');
  final _phoneController = TextEditingController();
  final _tbHostController = TextEditingController(text: 'eu.thingsboard.cloud');
  final _tbTokenController = TextEditingController();
  final _thresholdController = TextEditingController(text: '60');
  final _tbIntervalController = TextEditingController(text: '10');

  Interpreter? _interpreter;
  List<String> _labels = <String>[];
  List<String> _history = <String>[];
  bool _modelReady = false;
  bool _running = false;
  bool _busy = false;
  bool _smsEnabled = false;
  bool _thingsBoardEnabled = false;
  bool _sampleRecording = false;
  String? _sampleRecordingPath;
  String _sampleStatus = 'No labelled recordings saved yet.';
  List<_SavedRecording> _savedRecordings = <_SavedRecording>[];
  String _status = 'Loading local model...';
  String _prediction = '--';
  String _confidence = '--';
  String _smoothed = '--';
  String _lastAlertLabel = '';
  DateTime? _lastThingsBoardUpload;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadModel();
    _refreshSavedRecordings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _labelController.text = prefs.getString('label') ?? 'Elephant';
      _phoneController.text = prefs.getString('phone') ?? '';
      _tbHostController.text = prefs.getString('tbHost') ?? 'eu.thingsboard.cloud';
      _tbTokenController.text = prefs.getString('tbToken') ?? '';
      _thresholdController.text = prefs.getString('threshold') ?? '60';
      _tbIntervalController.text = prefs.getString('tbInterval') ?? '10';
      _smsEnabled = prefs.getBool('smsEnabled') ?? false;
      _thingsBoardEnabled = prefs.getBool('tbEnabled') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('label', _labelController.text.trim());
    await prefs.setString('phone', _phoneController.text.trim());
    await prefs.setString('tbHost', _tbHostController.text.trim());
    await prefs.setString('tbToken', _tbTokenController.text.trim());
    await prefs.setString('threshold', _thresholdController.text.trim());
    await prefs.setString('tbInterval', _tbIntervalController.text.trim());
    await prefs.setBool('smsEnabled', _smsEnabled);
    await prefs.setBool('tbEnabled', _thingsBoardEnabled);
  }

  Future<void> _loadModel() async {
    try {
      final rawLabels = await rootBundle.loadString(_labelsAsset);
      final labels = rawLabels.split(RegExp(r'\r?\n')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (labels.length < 2) throw Exception('The packaged labels file is missing or invalid.');
      final interpreter = await Interpreter.fromAsset(
        _modelAsset,
        options: InterpreterOptions()..threads = 2,
      );
      if (!mounted) {
        interpreter.close();
        return;
      }
      setState(() {
        _labels = labels;
        _interpreter = interpreter;
        _modelReady = true;
        _status = 'Ready: local EfficientNet-Lite0 TFLite model';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Model unavailable: $error');
    }
  }

  Future<Directory> _recordingsDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/EleAidRecordings');
    await directory.create(recursive: true);
    return directory;
  }

  String _safeRecordingLabel(String label) {
    final cleaned = label.trim().replaceAll(RegExp(r'[^A-Za-z0-9 _-]+'), '_').replaceAll(' ', '_');
    return cleaned.isEmpty ? 'Unknown' : cleaned;
  }

  Future<void> _refreshSavedRecordings() async {
    try {
      final root = await _recordingsDirectory();
      final files = root.listSync(recursive: true).whereType<File>().where((file) => file.path.toLowerCase().endsWith('.wav')).toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      final recordings = files.map((file) {
        final relative = file.path.substring(root.path.length + 1);
        final parts = relative.split(RegExp(r'[\\/]'));
        return _SavedRecording(file.path, parts.length > 1 ? parts.first : 'Unknown', parts.last);
      }).toList();
      if (mounted) setState(() { _savedRecordings = recordings; _sampleStatus = '${recordings.length} labelled recording(s) saved on this phone.'; });
    } catch (error) {
      if (mounted) setState(() => _sampleStatus = 'Could not read saved recordings: $error');
    }
  }

  Future<void> _startLabelledRecording() async {
    if (_running || _sampleRecording) return;
    final label = _recordLabelController.text.trim();
    final duration = double.tryParse(_sampleDurationController.text.trim());
    if (label.isEmpty) { _showError('Enter a label before recording.'); return; }
    if (duration == null || duration <= 0 || duration > 300) { _showError('Recording duration must be between 0 and 300 seconds.'); return; }
    if (!await _recorder.hasPermission()) { _showError('Microphone permission was not granted.'); return; }
    try {
      final root = await _recordingsDirectory();
      final labelDirectory = Directory('${root.path}/${_safeRecordingLabel(label)}');
      await labelDirectory.create(recursive: true);
      final path = '${labelDirectory.path}/${_safeRecordingLabel(label)}_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(
        RecordConfig(encoder: AudioEncoder.wav, sampleRate: _sampleRate, numChannels: 1),
        path: path,
      );
      if (mounted) setState(() { _sampleRecording = true; _sampleRecordingPath = path; _sampleStatus = 'Recording label "$label"... tap Stop and save when finished.'; });
    } catch (error) { _showError('Could not start labelled recording: $error'); }
  }

  Future<void> _stopLabelledRecording() async {
    if (!_sampleRecording) return;
    try {
      final recordedPath = await _recorder.stop();
      if (recordedPath == null || recordedPath.isEmpty) throw Exception('Recorder did not return a WAV file.');
      if (mounted) setState(() { _sampleRecording = false; _sampleRecordingPath = null; _sampleStatus = 'Saved labelled recording: ${File(recordedPath).uri.pathSegments.last}'; });
      await _refreshSavedRecordings();
    } catch (error) {
      if (mounted) setState(() { _sampleRecording = false; _sampleRecordingPath = null; });
      _showError('Could not save labelled recording: $error');
    }
  }

  Future<void> _deleteSavedRecording(_SavedRecording recording) async {
    try {
      await File(recording.path).delete();
      await _refreshSavedRecordings();
    } catch (error) { _showError('Could not delete recording: $error'); }
  }

  Future<void> _exportRecordings() async {
    final root = await _recordingsDirectory();
    final files = root.listSync(recursive: true).whereType<File>().where((file) => file.path.toLowerCase().endsWith('.wav')).toList();
    if (files.isEmpty) { _showError('There are no labelled recordings to export.'); return; }
    try {
      final archive = Archive();
      final manifest = <Map<String, String>>[];
      for (final file in files) {
        final relative = file.path.substring(root.path.length + 1).replaceAll('\\', '/');
        final bytes = await file.readAsBytes();
        archive.addFile(ArchiveFile('EleAidRecordings/$relative', bytes.length, bytes));
        final parts = relative.split('/');
        manifest.add({'file': relative, 'label': parts.length > 1 ? parts.first : 'Unknown'});
      }
      final readme = utf8.encode('Extract this ZIP and import each label folder in the desktop app, or use the desktop Import Android Recordings ZIP button.\n');
      archive.addFile(ArchiveFile('EleAidRecordings/README.txt', readme.length, readme));
      final manifestBytes = utf8.encode(jsonEncode({'format': 'EleAid labelled recordings v1', 'sample_rate': _sampleRate, 'files': manifest}));
      archive.addFile(ArchiveFile('EleAidRecordings/manifest.json', manifestBytes.length, manifestBytes));
      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) throw Exception('ZIP encoder returned no data.');
      final temp = await getTemporaryDirectory();
      final zipPath = '${temp.path}/eleaid_recordings_${DateTime.now().millisecondsSinceEpoch}.zip';
      await File(zipPath).writeAsBytes(encoded, flush: true);
      await Share.shareXFiles([XFile(zipPath, mimeType: 'application/zip')], text: 'EleAid labelled recordings for desktop training');
    } catch (error) { _showError('Could not export recordings: $error'); }
  }

  Future<void> _start() async {
    if (!_modelReady || _interpreter == null) {
      _showError('Build the APK with a trained EfficientNet-Lite0 model first.');
      return;
    }
    if (!await _recorder.hasPermission()) {
      _showError('Microphone permission was not granted.');
      return;
    }
    if (_smsEnabled) {
      if (_phoneController.text.trim().isEmpty) {
        _showError('Enter a phone number or disable SMS.');
        return;
      }
      if (_directSmsEnabled) {
        final permitted = await _native.invokeMethod<bool>('requestSmsPermission') ?? false;
        if (!permitted) {
          _showError('SMS permission was not granted.');
          return;
        }
      }
    }
    await _saveSettings();
    if (!mounted) return;
    setState(() {
      _running = true;
      _status = 'Running local inference';
      _history = <String>[];
      _lastAlertLabel = '';
    });
    while (_running && mounted) {
      await _recordAndPredict();
    }
  }

  Future<void> _stop() async {
    if (mounted) setState(() { _running = false; _status = 'Stopping'; });
    if (await _recorder.isRecording()) await _recorder.stop();
    if (mounted) setState(() => _status = 'Stopped');
  }

  Future<void> _recordAndPredict() async {
    if (_busy || !_running) return;
    _busy = true;
    String? path;
    try {
      final directory = await getTemporaryDirectory();
      path = '${directory.path}/eleaid_${DateTime.now().millisecondsSinceEpoch}.wav';
      if (mounted) setState(() => _status = 'Recording $_windowSeconds seconds...');
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: _sampleRate, numChannels: 1),
        path: path,
      );
      await Future<void>.delayed(const Duration(seconds: _windowSeconds));
      final recordedPath = await _recorder.stop();
      if (recordedPath == null) throw Exception('Recorder did not return a WAV file.');
      if (mounted) setState(() => _status = 'Running local TFLite inference...');
      final wav = await File(recordedPath).readAsBytes();
      final decoded = _decodeWav(wav);
      final samples = decoded.sampleRate == _sampleRate ? decoded.samples : _resample(decoded.samples, decoded.sampleRate, _sampleRate);
      await _predict(samples);
    } catch (error) {
      if (mounted) setState(() => _status = 'Error: $error');
      await Future<void>.delayed(const Duration(seconds: 2));
    } finally {
      if (path != null) {
        try { await File(path).delete(); } catch (_) {}
      }
      _busy = false;
    }
  }

  Future<void> _predict(List<double> samples) async {
    final interpreter = _interpreter;
    if (interpreter == null) return;
    final image = _melImage(samples);
    final output = List.generate(1, (_) => List<double>.filled(_labels.length, 0));
    interpreter.run(image, output);
    final probabilities = (output[0] as List).map((value) => (value as num).toDouble()).toList();
    var best = 0;
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[best]) {
        best = i;
      }
    }
    final label = _labels[best];
    final confidence = probabilities[best];
    _history = [..._history, label].takeLast(5).toList();
    final counts = <String, int>{};
    for (final item in _history) {
      counts[item] = (counts[item] ?? 0) + 1;
    }
    final mostCommon = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final confirmed = _history.length >= 5 && mostCommon.value >= 3;
    final target = _labelController.text.trim();
    final threshold = _threshold();
    final valid = confirmed && confidence >= threshold && (target.isEmpty || label == target);

    if (mounted) {
      setState(() {
        _prediction = label;
        _confidence = '${(confidence * 100).toStringAsFixed(1)}%';
        _smoothed = confirmed ? '${mostCommon.key} confirmed' : 'Collecting evidence';
        _status = valid ? 'Confirmed detection: $label' : 'Analysed locally';
      });
    }
    await _dispatchAlerts(label, confidence, probabilities, valid);
  }

  double _threshold() {
    final value = double.tryParse(_thresholdController.text.trim()) ?? 60;
    return (value > 1 ? value / 100 : value).clamp(0.0, 1.0).toDouble();
  }

  Future<void> _dispatchAlerts(String label, double confidence, List<double> probabilities, bool valid) async {
    if (!valid) _lastAlertLabel = '';
    if (valid && _smsEnabled && label != _lastAlertLabel) {
      final message = 'EleAid detected $label (${(confidence * 100).toStringAsFixed(1)}%)';
      if (_directSmsEnabled) {
        await _native.invokeMethod('sendSms', {
          'phone': _phoneController.text.trim(),
          'message': message,
        });
      } else if (mounted) {
        setState(() => _status = 'Confirmed detection: $label. Tap Compose SMS to send.');
      }
      _lastAlertLabel = label;
    }
    if (_thingsBoardEnabled) {
      final interval = double.tryParse(_tbIntervalController.text.trim()) ?? 10;
      final now = DateTime.now();
      if (_lastThingsBoardUpload == null || now.difference(_lastThingsBoardUpload!).inMilliseconds >= interval * 1000) {
        await _sendThingsBoard(label, confidence, probabilities, valid);
        _lastThingsBoardUpload = now;
      }
    }
  }

  Future<void> _sendThingsBoard(String label, double confidence, List<double> probabilities, bool valid) async {
    final host = _tbHostController.text.trim();
    final token = _tbTokenController.text.trim();
    if (host.isEmpty || token.isEmpty) return;
    final normalized = host.startsWith('http://') || host.startsWith('https://') ? host : 'https://$host';
    final uri = Uri.parse('$normalized/api/v1/$token/telemetry');
    final payload = <String, dynamic>{
      'animal_prediction_label': label,
      'animal_prediction_confidence': confidence,
      'animal_prediction_valid': valid,
      'animal_model_type': 'EfficientNet-Lite0 Mobile CNN/TFLite',
      'animal_uploaded_from': 'Android_local_tflite',
      'animal_client_time': DateTime.now().toIso8601String(),
    };
    for (var i = 0; i < probabilities.length && i < _labels.length; i++) {
      payload['animal_prob_${_labels[i].replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}'] = probabilities[i] * 100;
    }
    final response = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('ThingsBoard HTTP ${response.statusCode}');
  }

  Future<void> _testSms() async {
    if (_phoneController.text.trim().isEmpty) { _showError('Enter a phone number first.'); return; }
    try {
      const message = 'EleAid Android local TFLite SMS test';
      if (_directSmsEnabled) {
        final permitted = await _native.invokeMethod<bool>('requestSmsPermission') ?? false;
        if (!permitted) { _showError('SMS permission was not granted.'); return; }
        await _native.invokeMethod('sendSms', {'phone': _phoneController.text.trim(), 'message': message});
        if (mounted) setState(() => _status = 'Test SMS sent automatically through phone SIM');
      } else {
        await _native.invokeMethod('composeSms', {'phone': _phoneController.text.trim(), 'message': message});
        if (mounted) setState(() => _status = 'SMS composer opened; review and send the message');
      }
    } catch (error) { _showError('SMS failed: $error'); }
  }

  Future<void> _saveAndShowSettings() async { await _saveSettings(); if (mounted) setState(() => _status = 'Settings saved'); }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _running = false;
    _interpreter?.close();
    _recorder.dispose();
    _labelController.dispose();
    _recordLabelController.dispose();
    _sampleDurationController.dispose();
    _phoneController.dispose();
    _tbHostController.dispose();
    _tbTokenController.dispose();
    _thresholdController.dispose();
    _tbIntervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = _running;
    return Scaffold(
      appBar: AppBar(title: const Text('EleAid Independent Detector')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_directSmsEnabled
              ? 'Standalone field mode: inference runs locally with the packaged EfficientNet-Lite0 TFLite model. Automatic SMS uses the phone SIM. No inference API URL or API key is required.'
              : 'Standalone Play-friendly mode: inference runs locally with the packaged EfficientNet-Lite0 TFLite model. No inference API URL or API key is required. SMS uses the phone composer and requires user confirmation.', style: const TextStyle(fontSize: 16)))),
          const SizedBox(height: 12),
          Text('Model: ${_modelReady ? 'EfficientNet-Lite0 ready' : 'not available'}'),
          Text('Status: $_status'),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Collect labelled training audio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Record samples on the phone now. They are stored locally under a folder named after the label and can be exported for desktop training.'),
            const SizedBox(height: 12),
            TextField(controller: _recordLabelController, enabled: !_sampleRecording && !running, decoration: const InputDecoration(labelText: 'Recording label', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            if (_labels.isNotEmpty) Wrap(spacing: 6, children: _labels.take(12).map((label) => ActionChip(label: Text(label), onPressed: _sampleRecording || running ? null : () => setState(() => _recordLabelController.text = label))).toList()),
            const SizedBox(height: 8),
            TextField(controller: _sampleDurationController, enabled: !_sampleRecording && !running, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Recording duration (seconds)', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            Row(children: [Expanded(child: FilledButton.icon(onPressed: running ? null : (_sampleRecording ? _stopLabelledRecording : _startLabelledRecording), icon: Icon(_sampleRecording ? Icons.stop : Icons.fiber_manual_record), label: Text(_sampleRecording ? 'Stop and save' : 'Record labelled sample'))), const SizedBox(width: 8), OutlinedButton.icon(onPressed: _sampleRecording || running ? null : _exportRecordings, icon: const Icon(Icons.ios_share), label: const Text('Export ZIP'))]),
            const SizedBox(height: 6),
            Text(_sampleStatus, style: const TextStyle(color: Colors.grey)),
            if (_savedRecordings.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Recent recordings:'),
              ..._savedRecordings.take(8).map((recording) => ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text(recording.label), subtitle: Text(recording.fileName), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: _sampleRecording || running ? null : () => _deleteSavedRecording(recording)))),
            ],
          ]))),
          const SizedBox(height: 12),
          TextField(controller: _labelController, decoration: const InputDecoration(labelText: 'Alert target label (blank = any)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _thresholdController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Confidence threshold (%)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          SwitchListTile(title: Text(_directSmsEnabled ? 'Send automatic SMS through phone SIM' : 'Enable SMS composer prompts'), value: _smsEnabled, onChanged: running ? null : (value) => setState(() => _smsEnabled = value)),
          if (_smsEnabled) ...[
            TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Recipient phone number', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: running ? null : _testSms, child: Text(_directSmsEnabled ? 'Send test SMS' : 'Compose test SMS')),
            if (!_directSmsEnabled) const Text('Confirmed detections are shown in the app; tap the composer button to review and send an SMS.', style: TextStyle(color: Colors.grey)),
          ],
          SwitchListTile(title: const Text('Send ThingsBoard telemetry directly'), value: _thingsBoardEnabled, onChanged: running ? null : (value) => setState(() => _thingsBoardEnabled = value)),
          if (_thingsBoardEnabled) ...[
            TextField(controller: _tbHostController, decoration: const InputDecoration(labelText: 'ThingsBoard host', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _tbTokenController, obscureText: true, decoration: const InputDecoration(labelText: 'ThingsBoard device token', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _tbIntervalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Upload interval (seconds)', border: OutlineInputBorder())),
          ],
          const SizedBox(height: 12),
          Row(children: [Expanded(child: FilledButton.icon(onPressed: running ? null : _start, icon: const Icon(Icons.mic), label: const Text('Start'))), const SizedBox(width: 12), Expanded(child: OutlinedButton.icon(onPressed: running ? _stop : null, icon: const Icon(Icons.stop), label: const Text('Stop')))]),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: running ? null : _saveAndShowSettings, child: const Text('Save settings')),
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Prediction: $_prediction', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), Text('Confidence: $_confidence'), Text('Smoothed decision: $_smoothed')]))),
          const SizedBox(height: 12),
          const Text('The APK contains the model and labels generated by the desktop Build Android APK button.', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _SavedRecording {
  const _SavedRecording(this.path, this.label, this.fileName);
  final String path;
  final String label;
  final String fileName;
}

class _DecodedWav {
  const _DecodedWav(this.samples, this.sampleRate);
  final List<double> samples;
  final int sampleRate;
}

_DecodedWav _decodeWav(Uint8List bytes) {
  if (bytes.length < 44 || ascii.decode(bytes.sublist(0, 4)) != 'RIFF' || ascii.decode(bytes.sublist(8, 12)) != 'WAVE') throw Exception('Expected a PCM WAV recording.');
  final data = ByteData.sublistView(bytes);
  var offset = 12;
  var sampleRate = 0;
  var channels = 1;
  var bits = 16;
  var format = 1;
  var dataOffset = -1;
  var dataLength = 0;
  while (offset + 8 <= bytes.length) {
    final id = ascii.decode(bytes.sublist(offset, offset + 4), allowInvalid: true);
    final length = data.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (body + length > bytes.length) break;
    if (id == 'fmt ' && length >= 16) {
      format = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      bits = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      dataOffset = body;
      dataLength = length;
      break;
    }
    offset = body + length + (length.isOdd ? 1 : 0);
  }
  if (sampleRate <= 0 || dataOffset < 0 || channels <= 0) throw Exception('Invalid WAV format.');
  if (format != 1 || bits != 16) throw Exception('Only PCM16 WAV is supported.');
  final frameBytes = channels * 2;
  final frames = dataLength ~/ frameBytes;
  final samples = List<double>.filled(frames, 0);
  for (var frame = 0; frame < frames; frame++) {
    var total = 0.0;
    for (var channel = 0; channel < channels; channel++) {
      total += data.getInt16(dataOffset + frame * frameBytes + channel * 2, Endian.little) / 32768.0;
    }
    samples[frame] = total / channels;
  }
  return _DecodedWav(samples, sampleRate);
}

List<double> _resample(List<double> source, int fromRate, int toRate) {
  if (fromRate == toRate) return source;
  final length = (source.length * toRate / fromRate).round();
  return List<double>.generate(length, (index) {
    final position = index * fromRate / toRate;
    final left = position.floor().clamp(0, source.length - 1);
    final right = (left + 1).clamp(0, source.length - 1);
    final fraction = position - left;
    return source[left] * (1 - fraction) + source[right] * fraction;
  });
}

List<List<List<List<double>>>> _melImage(List<double> source) {
  final padded = List<double>.filled(source.length + _fftSize, 0);
  padded.setRange(_fftSize ~/ 2, _fftSize ~/ 2 + source.length, source);
  final frames = ((padded.length - _fftSize) / _hopSize).floor() + 1;
  final matrix = List.generate(_melCount, (_) => List<double>.filled(frames, 0));
  final filters = _melFilters();
  final window = List<double>.generate(_fftSize, (i) => 0.5 - 0.5 * math.cos(2 * math.pi * i / (_fftSize - 1)));
  var maxPower = 1e-10;
  for (var frame = 0; frame < frames; frame++) {
    final real = List<double>.filled(_fftSize, 0);
    final imaginary = List<double>.filled(_fftSize, 0);
    final start = frame * _hopSize;
    for (var i = 0; i < _fftSize; i++) {
      real[i] = padded[start + i] * window[i];
    }
    _fft(real, imaginary);
    final power = List<double>.generate(_fftSize ~/ 2 + 1, (i) => real[i] * real[i] + imaginary[i] * imaginary[i]);
    for (var mel = 0; mel < _melCount; mel++) {
      var value = 0.0;
      for (var bin = 0; bin < power.length; bin++) {
        value += power[bin] * filters[mel][bin];
      }
      matrix[mel][frame] = value;
      if (value > maxPower) maxPower = value;
    }
  }
  var minDb = 0.0;
  var maxDb = -double.infinity;
  final db = List.generate(_melCount, (mel) => List<double>.generate(frames, (frame) {
    final value = 10 * math.log(math.max(matrix[mel][frame], 1e-10) / maxPower) / math.ln10;
    minDb = math.min(minDb, value).toDouble();
    maxDb = math.max(maxDb, value).toDouble();
    return value;
  }));
  final image = List.generate(_imageSize, (_) => List.generate(_imageSize, (_) => List<double>.filled(3, 0)));
  final range = math.max(maxDb - minDb, 1e-9).toDouble();
  for (var mel = 0; mel < _imageSize; mel++) {
    for (var column = 0; column < _imageSize; column++) {
      final position = column * (frames - 1) / (_imageSize - 1);
      final left = position.floor().clamp(0, frames - 1);
      final right = (left + 1).clamp(0, frames - 1);
      final fraction = position - left;
      final value = ((db[mel][left] * (1 - fraction) + db[mel][right] * fraction) - minDb) / range;
      final normalized = value.clamp(0.0, 1.0).toDouble();
      image[mel][column] = [normalized, normalized, normalized];
    }
  }
  return [image];
}

List<List<double>> _melFilters() {
  final lowMel = _hzToMel(0);
  final highMel = _hzToMel(_sampleRate / 2);
  final points = List<double>.generate(_melCount + 2, (i) => _melToHz(lowMel + i * (highMel - lowMel) / (_melCount + 1)));
  final frequencies = List<double>.generate(_fftSize ~/ 2 + 1, (i) => i * _sampleRate / _fftSize);
  final filters = List.generate(_melCount, (_) => List<double>.filled(frequencies.length, 0));
  for (var mel = 0; mel < _melCount; mel++) {
    final left = points[mel];
    final center = points[mel + 1];
    final right = points[mel + 2];
    final enorm = 2 / math.max(right - left, 1e-12).toDouble();
    for (var bin = 0; bin < frequencies.length; bin++) {
      final frequency = frequencies[bin];
      final rising = (frequency - left) / math.max(center - left, 1e-12);
      final falling = (right - frequency) / math.max(right - center, 1e-12);
      filters[mel][bin] = math.max(0, math.min(rising, falling)).toDouble() * enorm;
    }
  }
  return filters;
}

double _hzToMel(double hz) => hz < 1000 ? hz * 3 / 200 : 15 + 27 * math.log(hz / 1000) / math.log(6.4);
double _melToHz(double mel) => mel < 15 ? mel * 200 / 3 : 1000 * math.exp((mel - 15) * math.log(6.4) / 27);

void _fft(List<double> real, List<double> imaginary) {
  final n = real.length;
  var j = 0;
  for (var i = 1; i < n; i++) {
    var bit = n >> 1;
    while ((j & bit) != 0) { j ^= bit; bit >>= 1; }
    j ^= bit;
    if (i < j) { final tr = real[i]; real[i] = real[j]; real[j] = tr; }
  }
  for (var length = 2; length <= n; length <<= 1) {
    final angle = -2 * math.pi / length;
    final wReal = math.cos(angle);
    final wImaginary = math.sin(angle);
    for (var start = 0; start < n; start += length) {
      var currentReal = 1.0;
      var currentImaginary = 0.0;
      for (var i = 0; i < length ~/ 2; i++) {
        final even = start + i;
        final odd = even + length ~/ 2;
        final oddReal = real[odd] * currentReal - imaginary[odd] * currentImaginary;
        final oddImaginary = real[odd] * currentImaginary + imaginary[odd] * currentReal;
        real[odd] = real[even] - oddReal;
        imaginary[odd] = imaginary[even] - oddImaginary;
        real[even] += oddReal;
        imaginary[even] += oddImaginary;
        final nextReal = currentReal * wReal - currentImaginary * wImaginary;
        currentImaginary = currentReal * wImaginary + currentImaginary * wReal;
        currentReal = nextReal;
      }
    }
  }
}

extension<T> on List<T> {
  Iterable<T> takeLast(int count) => skip(math.max(0, length - count).toInt());
}
