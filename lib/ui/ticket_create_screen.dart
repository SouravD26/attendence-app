import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../state/ticket_state.dart';

/// Full-screen "Raise a ticket", carrying the same fields as the web form in
/// ticket-new.php: subject, department (read-only), location, the training
/// question and the description.
///
/// Returns true once the ticket is raised.
Future<bool?> showTicketCreateScreen(
  BuildContext context, {
  required TicketState state,
  String? department,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TicketCreateScreen(state: state, department: department),
    ),
  );
}

class TicketCreateScreen extends StatefulWidget {
  const TicketCreateScreen({
    super.key,
    required this.state,
    this.department,
  });

  final TicketState state;

  /// Shown read-only. The server takes the department from the requester's own
  /// record and ignores anything sent, exactly as the web form does.
  final String? department;

  @override
  State<TicketCreateScreen> createState() => _TicketCreateScreenState();
}

class _TicketCreateScreenState extends State<TicketCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _locationText = TextEditingController();

  String? _location;

  /// Required with no default, matching the web form's radio pair - an
  /// employee has to answer rather than accept a pre-picked option.
  bool? _trainedBefore;
  bool _busy = false;

  /// Attached photos, capped to match the server.
  static const _maxPhotos = 5;
  final _picker = ImagePicker();
  final List<XFile> _photos = [];
  bool _attaching = false;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    _locationText.dispose();
    super.dispose();
  }

  /// The server validates `location` against the HRMS master list, so use the
  /// dropdown whenever tickets/locations was reachable, and fall back to free
  /// text only if it was not.
  String get _chosenLocation => widget.state.options.locations.isEmpty
      ? _locationText.text.trim()
      : (_location ?? '');

  Future<void> _addPhoto(ImageSource source) async {
    if (_photos.length >= _maxPhotos) {
      return _toast('You can attach up to $_maxPhotos photos.');
    }
    setState(() => _attaching = true);
    try {
      // Downscaled before it reaches memory: a full-resolution phone photo
      // base64-encodes to several megabytes and the server caps each at 5 MB.
      final shot = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (shot != null && mounted) setState(() => _photos.add(shot));
    } catch (_) {
      if (mounted) _toast('Could not attach that photo.');
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  void _pickSource() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(sheet);
                _addPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(sheet);
                _addPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Reads each photo as the data URI the API expects.
  Future<List<String>> _encodePhotos() async {
    final out = <String>[];
    for (final photo in _photos) {
      final bytes = await File(photo.path).readAsBytes();
      out.add('data:image/jpeg;base64,${base64Encode(bytes)}');
    }
    return out;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_chosenLocation.isEmpty) {
      return _toast('Choose the location this issue is at.');
    }
    if (_trainedBefore == null) {
      return _toast('Answer whether you have been trained on this before.');
    }

    setState(() => _busy = true);

    final List<String> encoded;
    try {
      encoded = await _encodePhotos();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      return _toast('Could not read one of the photos. Remove it and retry.');
    }

    final error = await widget.state.create(
      subject: _subject.text.trim(),
      body: _body.text.trim(),
      location: _chosenLocation,
      trainedBefore: _trainedBefore!,
      photos: encoded,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (error != null) return _toast(error);
    Navigator.pop(context, true);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locations = widget.state.options.locations;
    final department = (widget.department == null ||
            widget.department!.trim().isEmpty)
        ? 'Not set'
        : widget.department!;

    return Scaffold(
      appBar: AppBar(title: const Text('Raise a ticket')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.gutter,
            8,
            AppTheme.gutter,
            16,
          ),
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Submit ticket'),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.gutter,
            8,
            AppTheme.gutter,
            24,
          ),
          children: [
            const _FieldLabel('Subject'),
            TextFormField(
              controller: _subject,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Short summary of the problem',
              ),
              validator: (v) => (v == null || v.trim().length < 4)
                  ? 'Give the issue a short title.'
                  : null,
            ),
            const SizedBox(height: 18),

            const _FieldLabel('Department'),
            InputDecorator(
              decoration: InputDecoration(
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                suffixIcon: Icon(
                  Icons.lock_outline_rounded,
                  size: 17,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              child: Text(
                department,
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Taken from your employee record.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 18),

            const _FieldLabel('Location'),
            if (locations.isEmpty)
              TextFormField(
                controller: _locationText,
                decoration: const InputDecoration(hintText: 'Location'),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _location,
                isExpanded: true,
                decoration: const InputDecoration(hintText: 'Select location…'),
                items: [
                  for (final l in locations)
                    DropdownMenuItem(value: l, child: Text(l)),
                ],
                onChanged: (v) => setState(() => _location = v),
              ),
            const SizedBox(height: 20),

            const _FieldLabel(
              'Have you been trained to troubleshoot this issue before?',
            ),
            Row(
              children: [
                Expanded(
                  child: _ChoiceTile(
                    label: 'Yes',
                    selected: _trainedBefore == true,
                    onTap: () => setState(() => _trainedBefore = true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ChoiceTile(
                    label: 'No',
                    selected: _trainedBefore == false,
                    onTap: () => setState(() => _trainedBefore = false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            const _FieldLabel('Description'),
            TextFormField(
              controller: _body,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What happened? What did you expect? '
                    'Any steps to reproduce?',
                alignLabelWithHint: true,
              ),
              validator: (v) => (v == null || v.trim().length < 10)
                  ? 'Describe the problem so IT can act on it.'
                  : null,
            ),
            const SizedBox(height: 20),

            const _FieldLabel('Photos'),
            Text(
              'Optional, up to $_maxPhotos. A picture of the screen or the '
              'device usually explains it faster than words.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < _photos.length; i++)
                  _Thumb(
                    file: File(_photos[i].path),
                    onRemove: () => setState(() => _photos.removeAt(i)),
                  ),
                if (_photos.length < _maxPhotos)
                  _AddPhotoTile(
                    busy: _attaching,
                    onTap: _attaching ? null : _pickSource,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One attached photo, with a remove button.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.file, required this.onRemove});

  final File file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 86,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(file, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(100),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: busy
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_a_photo_outlined,
                    size: 21,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Add',
                    style: TextStyle(fontSize: 12, color: scheme.primary),
                  ),
                ],
              ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A radio in the shape of a tappable card - easier to hit than a radio dot.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 19,
              color: selected ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? scheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
