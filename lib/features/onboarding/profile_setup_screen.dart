import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/sanitizer.dart';
import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/backend.dart';
import '../../providers.dart';
import 'dob.dart';

const _allInterests = [
  'Travel',
  'Music',
  'Cafés',
  'Photography',
  'Trekking',
  'Books',
  'Movies',
  'Football',
  'Cricket',
  'Dance',
  'Cooking',
  'Fitness',
  'Yoga',
  'Art',
  'Gaming',
  'Startups',
  'Beaches',
  'Pets',
  'Poetry',
  'Food',
];

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key, required this.isOnboarding});
  final bool isOnboarding;

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  DateTime? _dob;
  int? _lockedAge;
  final _bio = TextEditingController();
  String _city = AppConfig.keralaCities.first;
  final _interests = <String>{};
  Uint8List? _primary;
  String? _existingPrimary;
  List<String> _existingGallery = const [];
  final _newGallery = <Uint8List>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isOnboarding) _prefill();
  }

  Future<void> _prefill() async {
    final p = await ref.read(myProfileProvider.future);
    final priv = await ref.read(myPrivateProfileProvider.future);
    if (!mounted || p == null) return;
    setState(() {
      _name.text = p.fullName;
      _lockedAge = p.age;
      _bio.text = p.bio;
      _city = AppConfig.keralaCities.contains(p.city) ? p.city : AppConfig.keralaCities.first;
      _existingPrimary = p.primaryPhoto;
      _existingGallery = priv.gallery;
      _interests.addAll(priv.interests);
    });
  }

  Future<Uint8List?> _pick() async {
    try {
      return await ref.read(mediaProvider).pickCompressedPhoto();
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.image_not_supported_outlined);
      return null;
    }
  }

  Future<void> _save() async {
    // Strip contact info rather than just rejecting it.
    final cleanBio = ContactSanitizer.sanitize(_bio.text);
    if (cleanBio != _bio.text.trim()) {
      _bio.text = cleanBio;
      showSnack(context, 'Removed phone numbers / handles / links from your bio.', icon: Icons.shield_outlined);
    }
    if (!_form.currentState!.validate()) return;
    if (widget.isOnboarding && _dob == null) {
      showSnack(context, 'Add your date of birth. Vouby is for adults only.');
      return;
    }
    if (_primary == null && _existingPrimary == null && !AppConfig.isDemo) {
      showSnack(context, 'Add a primary photo — it’s the only one strangers see.');
      return;
    }
    setState(() => _busy = true);
    try {
      final backend = ref.read(backendProvider);
      // The DOB is stored privately and locked; the server computes the age.
      if (widget.isOnboarding && !await backend.hasDob()) await backend.setDob(_dob!);
      final pendingReview = await backend.saveProfile(
        ProfileDraft(
          fullName: _name.text.trim(),
          city: _city,
          bio: cleanBio,
          interests: _interests.toList(),
          primaryPhotoWebp: _primary,
          newGalleryWebp: _newGallery,
        ),
      );
      ref.invalidate(myProfileProvider);
      ref.invalidate(myPrivateProfileProvider);
      ref.invalidate(feedProvider);
      if (mounted && pendingReview > 0) {
        showSnack(
          context,
          '$pendingReview photo${pendingReview == 1 ? ' is' : 's are'} being reviewed. They’ll appear once approved.',
          icon: Icons.hourglass_top_rounded,
        );
      }
      if (mounted && !widget.isOnboarding) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final galleryCount = _existingGallery.length + _newGallery.length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.isOnboarding ? 'Create your profile' : 'Edit profile')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Center(
              child: GestureDetector(
                onTap: () async {
                  final b = await _pick();
                  if (b != null) setState(() => _primary = b);
                },
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: SizedBox(
                        width: 150,
                        height: 190,
                        child: _primary != null
                            ? Image.memory(_primary!, fit: BoxFit.cover)
                            : _existingPrimary != null
                            ? ProfilePhoto(url: _existingPrimary, name: _name.text)
                            : Container(
                                color: context.fc.surface,
                                child: Icon(Icons.add_a_photo_outlined, size: 40, color: context.fc.muted),
                              ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: context.fc.accent,
                        child: Icon(Icons.edit, size: 16, color: context.fc.paper),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text('Primary photo · visible on your public card', style: TextStyle(color: context.fc.muted, fontSize: 12)),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Required'
                  : ContactSanitizer.containsContactInfo(v)
                  ? 'No phone numbers, handles or links'
                  : null,
            ),
            const SizedBox(height: 12),
            if (widget.isOnboarding) ...[
              DobField(value: _dob, onChanged: (d) => setState(() => _dob = d)),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(
                  'Others see your age, never your date of birth. It can’t be changed later.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.fc.muted),
                ),
              ),
              const SizedBox(height: 12),
            ] else if (_lockedAge != null) ...[
              InfoChip(icon: PhosphorIconsRegular.cake, label: 'Age $_lockedAge · from your date of birth'),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _city,
                    decoration: const InputDecoration(labelText: 'District / City'),
                    items: [for (final c in AppConfig.keralaCities) DropdownMenuItem(value: c, child: Text(c))],
                    onChanged: (v) => setState(() => _city = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bio,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Bio', helperText: 'No phone numbers, @handles or links'),
              onChanged: (_) => setState(() {}),
              validator: (v) => ContactSanitizer.containsContactInfo(v ?? '') ? 'Contact details aren’t allowed in bios' : null,
            ),
            const SizedBox(height: 16),
            _SectionTitle(icon: Icons.interests_outlined, text: 'Interests'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final i in _allInterests)
                  FilterChip(
                    label: Text(i),
                    labelStyle: TextStyle(color: _interests.contains(i) ? context.fc.paper : context.fc.ink),
                    selected: _interests.contains(i),
                    onSelected: (s) => setState(() => s ? _interests.add(i) : _interests.remove(i)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _SectionTitle(icon: Icons.photo_library_outlined, text: 'More photos ($galleryCount/9)'),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (final u in _existingGallery)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ProfilePhoto(url: u, name: ''),
                  ),
                for (final b in _newGallery)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(b, fit: BoxFit.cover),
                  ),
                if (galleryCount < 9)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final b = await _pick();
                      if (b != null) setState(() => _newGallery.add(b));
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.fc.surface,
                        border: Border.all(color: context.fc.hair),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.add, color: context.fc.ink),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(widget.isOnboarding ? 'Start discovering' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: context.fc.muted),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );
}
