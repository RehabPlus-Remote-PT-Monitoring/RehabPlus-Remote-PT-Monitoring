import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/diagnostic_logger.dart';
import '../services/profile_service.dart';
import '../widgets/profile_avatar.dart';

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

class EditProfileScreen extends StatefulWidget {
  final ProfileData initial;
  const EditProfileScreen({super.key, required this.initial});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with SingleTickerProviderStateMixin {
  static const Color primaryTeal = Color(0xFF23A8AA);
  static const Color darkTeal = Color(0xFF0D6E71);
  static const String _tag = 'EditProfile';

  final DiagnosticLogger _logger = DiagnosticLogger.I;

  /// True while the photo sheet / camera / gallery is open, so a second tap
  /// can't open two pickers (image_picker throws "already_active").
  bool _pickingPhoto = false;

  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

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
    final source = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      // Light like the rest of this screen, even when the phone is in dark mode.
      backgroundColor: Colors.white,
      builder: (ctx) => Theme(
        data: ThemeData.light(useMaterial3: true),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_camera_outlined,
                  color: primaryTeal,
                ),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: primaryTeal,
                ),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              if (_photo != null)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red[700]),
                  title: const Text('Remove photo'),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
            ],
          ),
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

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();

    _logger.info(_tag, 'Screen opened');
  }

  @override
  void dispose() {
    _ctrl.dispose();
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
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F4),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAvatarSection(),
                        const SizedBox(height: 24),
                        _sectionLabel(
                          'Personal Info',
                          Icons.person_outline_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildCard([
                          // The email (the login) and rehab info are managed by the clinic.
                          _field(
                            _nameCtrl,
                            'Full Name',
                            Icons.person_outline,
                            keyboardType: TextInputType.name,
                            validator: _requiredName,
                            autofillHints: const [AutofillHints.name],
                            capitalization: TextCapitalization.words,
                          ),
                          _divider(),
                          _field(
                            _emailCtrl,
                            'Email',
                            Icons.email_outlined,
                            readOnly: true,
                          ),
                          _divider(),
                          _field(
                            _phoneCtrl,
                            'Phone',
                            Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            validator: _phone,
                            autofillHints: const [AutofillHints.telephoneNumber],
                          ),
                          _divider(),
                          _field(
                            _dobCtrl,
                            'Date of Birth',
                            Icons.cake_outlined,
                            validator: _required,
                            autofillHints: const [AutofillHints.birthday],
                          ),
                        ]),
                        const SizedBox(height: 20),
                        _sectionLabel(
                          'Rehab Info',
                          Icons.medical_services_outlined,
                        ),
                        const SizedBox(height: 12),
                        _buildCard([
                          _field(
                            _conditionCtrl,
                            'Condition',
                            Icons.medical_services_outlined,
                            readOnly: true,
                          ),
                          _divider(),
                          _field(
                            _therapistCtrl,
                            'Therapist',
                            Icons.person_pin_outlined,
                            readOnly: true,
                          ),
                        ]),
                        const SizedBox(height: 28),
                        _buildSaveButton(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [darkTeal, Color(0xFF1A8587), primaryTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Update Account',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Update your personal information',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _isSaving ? null : _choosePhoto,
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
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 17,
                      color: primaryTeal,
                    ),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _isSaving ? null : _choosePhoto,
            child: Text(
              _photo == null ? 'Add profile picture' : 'Change profile picture',
              style: const TextStyle(
                color: primaryTeal,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: primaryTeal),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(children: children),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool readOnly = false,
    Iterable<String>? autofillHints,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        readOnly: readOnly,
        validator: validator,
        autofillHints: readOnly ? null : autofillHints,
        textCapitalization: capitalization,
        style: const TextStyle(
          fontSize: 14,
          color: Colors.black87,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(
            icon,
            size: 18,
            color: readOnly ? Colors.black26 : primaryTeal,
          ),
          labelText: label,
          labelStyle: TextStyle(
            fontSize: 13,
            color: readOnly ? Colors.black26 : Colors.black45,
          ),
          border: InputBorder.none,
          suffixIcon: readOnly
              ? const Icon(Icons.lock_outline, size: 14, color: Colors.black26)
              : null,
        ),
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, color: Color(0xFFF0F0F0));

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

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryTeal,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Save Changes',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}
