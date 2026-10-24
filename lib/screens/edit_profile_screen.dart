import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_palette.dart';
import '../core/diagnostic_logger.dart';
import '../services/profile_service.dart';
import '../widgets/ios_list.dart';
import '../widgets/ios_page.dart';
import '../widgets/pressable.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_parts.dart';

class ProfileData {
  final String name;
  final String email;
  final String phone;
  final String dob;
  final String condition;
  final String therapist;

  /// When the patient's program started (patients/{uid}.createdAt).
  final DateTime? programStart;

  /// Profile picture (JPEG bytes), or null for the default icon.
  final Uint8List? photo;

  const ProfileData({
    required this.name,
    required this.email,
    required this.phone,
    required this.dob,
    required this.condition,
    this.therapist = '',
    this.programStart,
    this.photo,
  });
}

/// Edit Profile: an iOS form (label + field rows in grouped sections) under
/// a large title, with Save pinned at the bottom. Pops with the saved
/// [ProfileData]; the caller shows the new details, so no "saved" message.
class EditProfileScreen extends StatefulWidget {
  final ProfileData initial;

  /// Name of the screen underneath, shown next to the back chevron
  /// ("‹ Profile" from the Profile tab, "‹ Account Info" from there).
  final String previousPageTitle;

  const EditProfileScreen({
    super.key,
    required this.initial,
    this.previousPageTitle = 'Profile',
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const String _tag = 'EditProfile';

  final DiagnosticLogger _logger = DiagnosticLogger.I;

  /// True while the photo sheet / camera / gallery is open, so a second tap
  /// can't open two pickers (image_picker throws "already_active").
  bool _pickingPhoto = false;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _dobCtrl;
  late final TextEditingController _conditionCtrl;
  late final TextEditingController _therapistCtrl;

  bool _isSaving = false;

  /// The photo shown in the form; saved with Save Changes.
  late Uint8List? _photo = widget.initial.photo;
  bool _photoChanged = false;

  Future<void> _choosePhoto() async {
    if (_pickingPhoto) return;
    _pickingPhoto = true;
    try {
      await _choosePhotoUnguarded();
    } catch (e, st) {
      // Permission plugin or file read failures: report, never crash.
      _logger.error(_tag, 'Choosing a photo failed', null, e, st);
      _snack('Could not open the photo. Please try again.');
    } finally {
      _pickingPhoto = false;
    }
  }

  Future<void> _choosePhotoUnguarded() async {
    // iOS action sheet. Returns an ImageSource, 'remove', or null when
    // cancelled (Cancel button or a tap outside).
    final source = await showCupertinoModalPopup<Object>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Profile picture'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            child: const Text('Take a photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            child: const Text('Choose from gallery'),
          ),
          if (_photo != null)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, 'remove'),
              child: const Text('Remove photo'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (source == null || !mounted) return;
    if (source == 'remove') {
      _logger.info(_tag, 'Photo removed (not saved yet)');
      setState(() {
        _photo = null;
        _photoChanged = true;
      });
      return;
    }
    final imageSource = source as ImageSource;
    // The app declares the camera permission (for exercises), so Android
    // requires it to be granted before another app's camera can be used.
    if (imageSource == ImageSource.camera &&
        !(await Permission.camera.request()).isGranted) {
      _logger.warn(_tag, 'Camera permission denied for profile photo');
      _snack('Allow camera access in your phone settings to take a photo.');
      return;
    }
    try {
      // Small enough to store with the profile (see ProfileService.savePhoto).
      final file = await ImagePicker().pickImage(
        source: imageSource,
        maxWidth: ProfileService.photoSize,
        maxHeight: ProfileService.photoSize,
        imageQuality: 75,
        preferredCameraDevice: CameraDevice.front,
      );
      if (file == null) return; // cancelled
      final bytes = await file.readAsBytes();
      if (bytes.length > ProfileService.maxPhotoBytes) {
        _logger.warn(_tag, 'Photo too large', {
          'bytes': bytes.length,
          'max': ProfileService.maxPhotoBytes,
        });
        _snack('That photo is too large. Please choose another one.');
        return;
      }
      _logger.info(_tag, 'Photo chosen (not saved yet)', {
        'source': imageSource.name,
        'bytes': bytes.length,
      });
      if (!mounted) return;
      setState(() {
        _photo = bytes;
        _photoChanged = true;
      });
    } on PlatformException catch (e, st) {
      _logger.warn(_tag, 'Image picker failed', {'code': e.code}, e, st);
      _snack('Could not open the photo. Please try again.');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initial.name);
    _emailCtrl = TextEditingController(text: widget.initial.email);
    _phoneCtrl = TextEditingController(text: widget.initial.phone);
    _dobCtrl = TextEditingController(text: widget.initial.dob);
    _conditionCtrl = TextEditingController(text: widget.initial.condition);
    _therapistCtrl = TextEditingController(text: widget.initial.therapist);

    _logger.info(_tag, 'Screen opened');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _dobCtrl.dispose();
    _conditionCtrl.dispose();
    _therapistCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) {
      _logger.info(_tag, 'Save blocked by validation');
      return;
    }
    setState(() => _isSaving = true);
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final dob = _dobCtrl.text.trim();
    // Which fields changed, never their values (personal data).
    _logger.info(_tag, 'Saving profile', {
      'nameChanged': name != widget.initial.name,
      'phoneChanged': phone != widget.initial.phone,
      'dobChanged': dob != widget.initial.dob,
      'photoChanged': _photoChanged,
    });
    try {
      ProfileService().saveContact(name: name, phone: phone, dob: dob);
      if (_photoChanged) ProfileService().savePhoto(_photo);
    } catch (e, st) {
      // Thrown synchronously when signed out (or, in theory, for a value the
      // validators above already reject); the upload itself runs in the
      // background and ProfileService logs its result.
      _logger.error(_tag, 'Saving profile failed', null, e, st);
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Please sign in again.')),
      );
      return;
    }
    Navigator.pop(
      context,
      ProfileData(
        name: name,
        email: widget.initial.email,
        phone: phone,
        dob: dob,
        condition: widget.initial.condition,
        therapist: widget.initial.therapist,
        programStart: widget.initial.programStart,
        photo: _photo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The Form wraps the whole page so the fields inside the sliver list
    // and the Save button share one validation state.
    return Form(
      key: _formKey,
      child: IosPage(
        title: 'Edit Profile',
        previousPageTitle: widget.previousPageTitle,
        bottom: _buildSaveButton(),
        children: [
          _buildAvatarSection(),
          // The email (the login) and rehab info are managed by the clinic.
          IosSection(
            header: 'Personal Info',
            hasLeading: false,
            children: [
              ProfileFormRow(
                label: 'Full Name',
                controller: _nameCtrl,
                keyboardType: TextInputType.name,
                validator: _requiredName,
                autofillHints: const [AutofillHints.name],
                capitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
              ),
              ProfileFormRow(
                label: 'Email',
                controller: _emailCtrl,
                readOnly: true,
              ),
              ProfileFormRow(
                label: 'Phone',
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                validator: _phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                textInputAction: TextInputAction.next,
              ),
              ProfileFormRow(
                label: 'Date of Birth',
                controller: _dobCtrl,
                validator: _required,
                autofillHints: const [AutofillHints.birthday],
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
          IosSection(
            header: 'Rehab Info',
            footer:
                'Your email, condition and therapist are managed by the '
                'clinic.',
            hasLeading: false,
            children: [
              ProfileFormRow(
                label: 'Condition',
                controller: _conditionCtrl,
                readOnly: true,
              ),
              ProfileFormRow(
                label: 'Therapist',
                controller: _therapistCtrl,
                readOnly: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The photo with a camera badge, and a text button under it. Both open
  /// the photo action sheet.
  Widget _buildAvatarSection() {
    final palette = context.palette;
    final pickPhoto = _isSaving ? null : _choosePhoto;
    final buttonLabel =
        _photo == null ? 'Add profile picture' : 'Change profile picture';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Center(
        child: Column(
          children: [
            Pressable(
              onTap: pickPhoto,
              pressedScale: 0.94,
              semanticLabel: buttonLabel,
              child: Stack(
                children: [
                  ProfileAvatar(photo: _photo, size: 96),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: palette.surface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.camera_fill,
                        size: 17,
                        color: AppPalette.teal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            CupertinoButton(
              minimumSize: const Size(44, 44),
              onPressed: pickPhoto,
              child: Text(
                buttonLabel,
                style: const TextStyle(
                  fontSize: 17,
                  color: AppPalette.teal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Lengths match the Firestore rules (name ≤ 100, phone/date of birth ≤ 30).
  String? _required(String? v) => _check(v, 30);
  String? _requiredName(String? v) => _check(v, 100);

  String? _check(String? v, int max) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Required';
    return t.length > max ? 'Must be $max characters or fewer' : null;
  }

  /// Digits plus the usual separators (+, spaces, dashes, dots, brackets),
  /// with at least one digit. Keeps stray text out of the clinic's records.
  static final RegExp _phonePattern = RegExp(r'^[0-9+()\-.\s]+$');

  String? _phone(String? v) {
    final basic = _check(v, 30);
    if (basic != null) return basic;
    final t = v!.trim();
    if (!_phonePattern.hasMatch(t) || !t.contains(RegExp('[0-9]'))) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  /// Pinned under the form (IosPage.bottom), so it stays reachable however
  /// far the form is scrolled.
  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: _isSaving ? null : _save,
        style: FilledButton.styleFrom(
          backgroundColor: AppPalette.teal,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator.adaptive(
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Save Changes',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}
