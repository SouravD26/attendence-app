import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../core/device_services.dart';
import '../core/theme.dart';
import '../data/models.dart';

/// Full-screen punch capture: live camera preview, location resolved in the
/// background, shutter, then a review step before committing.
///
/// Replaces the old bottom sheet, which handed the selfie off to the system
/// camera app. Everything now happens inside the app, so the user never leaves
/// and we control the framing, the front lens and the timing of the fix.
///
/// Returns the [PunchContext] to record, or null if the user backs out.
Future<PunchContext?> showPunchScreen(
  BuildContext context, {
  required bool checkingIn,
  required DeviceServices services,
}) {
  return Navigator.of(context).push<PunchContext>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PunchScreen(checkingIn: checkingIn, services: services),
    ),
  );
}

class PunchScreen extends StatefulWidget {
  const PunchScreen({
    super.key,
    required this.checkingIn,
    required this.services,
  });

  final bool checkingIn;
  final DeviceServices services;

  @override
  State<PunchScreen> createState() => _PunchScreenState();
}

class _PunchScreenState extends State<PunchScreen> with WidgetsBindingObserver {
  static final _clock = DateFormat('hh:mm:ss a');
  static final _day = DateFormat('EEEE, d MMMM');

  CameraController? _camera;
  bool _cameraReady = false;
  bool _isFrontCamera = false;
  String? _cameraError;

  Position? _position;
  LocationResult? _locationResult;
  String _address = 'Getting your location…';
  bool _locating = true;

  XFile? _shot;
  bool _capturing = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
    _resolveLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  /// The OS tears the camera down when the app goes to the background; rebuild
  /// it on the way back rather than showing a frozen last frame.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      if (mounted) setState(() => _cameraReady = false);
    } else if (state == AppLifecycleState.resumed && _shot == null) {
      _startCamera();
      // GPS is often toggled from the notification shade rather than the
      // settings screen, so re-check on every resume while still blocked.
      if (!_hasLocation && !_locating) _resolveLocation();
    }
  }

  Future<void> _startCamera() async {
    final description = await widget.services.selfieCamera();
    if (description == null) {
      if (mounted) {
        setState(() => _cameraError = 'No camera available on this device.');
      }
      return;
    }

    final controller = CameraController(
      description,
      // Lower than `medium` on purpose: the selfie only needs to be good
      // enough to verify who punched, and this is the single biggest lever
      // on upload time - a smaller JPEG means a faster POST body over
      // mobile data, with no extra network round trips to pay for it.
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraReady = true;
        _isFrontCamera =
            description.lensDirection == CameraLensDirection.front;
        _cameraError = null;
      });
    } on CameraException catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _cameraError = e.code == 'CameraAccessDenied'
            ? 'Camera permission is required to punch. Enable it in Settings.'
            : 'Could not start the camera. ${e.description ?? e.code}';
      });
    }
  }

  Future<void> _resolveLocation() async {
    setState(() {
      _locating = true;
      _address = 'Getting your location…';
    });

    final result = await widget.services.resolveLocation();
    if (!mounted) return;

    setState(() {
      _locationResult = result;
      _position = result.location?.position;
      _address = result.location?.address ?? result.message;
      _locating = false;
    });
  }

  /// Sends the employee to the setting that unblocks them, then re-checks on
  /// the way back rather than making them tap refresh.
  Future<void> _fixLocation() async {
    final result = _locationResult;
    if (result == null) return;

    final opened = await widget.services.openSettingsFor(result.block);
    if (!mounted || !opened) return;
    await _resolveLocation();
  }

  Future<void> _capture() async {
    final controller = _camera;
    if (controller == null || !_cameraReady || _capturing) return;

    // Attendance cannot be marked without a location, so refuse at the shutter
    // rather than letting someone frame and shoot a selfie that can never be
    // submitted.
    if (!_hasLocation) {
      _toast(_locationResult?.message ??
          'Location is required to mark attendance.');
      return;
    }

    setState(() => _capturing = true);
    try {
      final shot = await controller.takePicture();
      if (!mounted) return;
      setState(() => _shot = shot);
    } on CameraException catch (_) {
      if (!mounted) return;
      _toast('Could not take the photo. Try again.');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _retake() {
    setState(() => _shot = null);
    // The controller stayed alive through review, so the preview resumes.
    if (!_cameraReady) _startCamera();
  }

  Future<void> _confirm() async {
    final shot = _shot;
    final position = _position;
    if (shot == null || position == null || _confirming) return;

    setState(() => _confirming = true);
    try {
      final context = PunchContext(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        address: _address,
        selfieBase64: await DeviceServices.encodeSelfie(shot.path),
        selfiePath: shot.path,
      );
      if (!mounted) return;
      Navigator.pop(this.context, context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _confirming = false);
      _toast('Could not read the photo. Please retake it.');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
  }

  bool get _hasLocation => _position != null;
  Color get _accent => widget.checkingIn ? AppTheme.success : AppTheme.danger;

  @override
  Widget build(BuildContext context) {
    final reviewing = _shot != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          reviewing ? _review() : _preview(),

          // Scrim so the white overlay text stays readable on any frame.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.28, 0.62, 1.0],
                colors: [
                  Color(0xB3000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0xCC000000),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _topBar(),
                const Spacer(),
                _locationCard(),
                _locationAction(),
                const SizedBox(height: 16),
                reviewing ? _reviewControls() : _captureControls(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ camera

  Widget _preview() {
    if (_cameraError != null) return _cameraFallback(_cameraError!);
    final controller = _camera;
    if (controller == null || !_cameraReady) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    // Show the whole sensor frame, letterboxed against the black background.
    //
    // Filling the screen with BoxFit.cover crops the 4:3 frame to the phone's
    // much taller aspect, and the preview and the saved JPEG do not lose the
    // same edges — which read as the photo zooming in the moment you tapped
    // the shutter. CameraPreview already wraps itself in the correct
    // AspectRatio, so centring it is all that is needed to show every pixel
    // the camera will actually capture.
    return Center(child: CameraPreview(controller));
  }

  /// Android mirrors the front-camera *preview* so framing feels like a
  /// mirror, but `takePicture` writes the un-mirrored frame — which made the
  /// face jump sides the moment the shutter fired. Flip the review back so
  /// what you confirm is what you framed.
  Widget _review() {
    // BoxFit.contain, to match the uncropped preview above — what you framed
    // is exactly what you review and exactly what is uploaded.
    final image = Image.file(
      File(_shot!.path),
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
    );

    if (!_isFrontCamera) return image;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
      child: image,
    );
  }

  Widget _cameraFallback(String message) => ColoredBox(
        color: const Color(0xFF14181F),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.no_photography_outlined,
                  color: Colors.white54,
                  size: 40,
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 18),
                OutlinedButton(
                  onPressed: _startCamera,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );

  // ----------------------------------------------------------------- chrome

  Widget _topBar() {
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            tooltip: 'Cancel',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.checkingIn ? 'Check in' : 'Check out',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _day.format(now),
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              _clock.format(now),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationCard() {
    final accuracy = _position?.accuracy;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _hasLocation
                ? AppTheme.success.withValues(alpha: 0.5)
                : AppTheme.warning.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _hasLocation
                  ? Icons.location_on_rounded
                  : Icons.location_off_outlined,
              size: 20,
              color: _hasLocation ? AppTheme.success : AppTheme.warning,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  if (_hasLocation && accuracy != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'Accurate to ${accuracy.round()} m  ·  '
                        '${DeviceServices.coordinatesOf(_position!)}',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (_locating)
              const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              )
            else
              IconButton(
                onPressed: _resolveLocation,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                color: Colors.white70,
                tooltip: 'Refresh location',
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }

  /// Full-width button that opens the exact setting standing in the way.
  /// Only shown when there is a setting to open — a timed-out fix just needs
  /// the refresh button above.
  Widget _locationAction() {
    final label = _locationResult?.actionLabel;
    if (_hasLocation || _locating || label == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.gutter,
        10,
        AppTheme.gutter,
        0,
      ),
      child: FilledButton.icon(
        onPressed: _fixLocation,
        icon: const Icon(Icons.my_location_rounded, size: 19),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.warning,
          minimumSize: const Size.fromHeight(48),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- controls

  Widget _captureControls() {
    // No location, no attendance — the shutter stays inert.
    final ready = _cameraReady && !_capturing && _hasLocation;

    final String hint;
    if (_hasLocation) {
      hint = 'Center your face and tap the shutter';
    } else if (_locating) {
      hint = 'Getting your location…';
    } else {
      hint = _locationResult?.message ??
          'Location is required to mark attendance.';
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
          child: Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _hasLocation ? Colors.white70 : AppTheme.warning,
              fontSize: 12.5,
            ),
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: ready ? _capture : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: ready ? Colors.white : Colors.white30,
                width: 3.5,
              ),
            ),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: _capturing ? 30 : 58,
                height: _capturing ? 30 : 58,
                decoration: BoxDecoration(
                  color: ready ? _accent : Colors.white24,
                  borderRadius:
                      BorderRadius.circular(_capturing ? 8 : 100),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _reviewControls() {
    // The server rejects a punch without coordinates, so block it here with an
    // explanation rather than letting it fail on submit.
    final blocked = !_hasLocation;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
      child: Column(
        children: [
          if (blocked) ...[
            const Text(
              'Your location is required. Tap refresh above, then confirm.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.warning, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _confirming ? null : _retake,
                  icon: const Icon(Icons.replay_rounded, size: 19),
                  label: const Text('Retake'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    minimumSize: const Size(0, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: (blocked || _confirming) ? null : _confirm,
                  icon: _confirming
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 20),
                  label: Text(
                    widget.checkingIn ? 'Check in now' : 'Check out now',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    minimumSize: const Size(0, 54),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
