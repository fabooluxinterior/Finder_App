import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/sanitizer.dart';
import '../../core/widgets.dart';
import '../../data/backend.dart';
import '../../providers.dart';

const _allInterests = [
  'Travel', 'Music', 'Cafés', 'Photography', 'Trekking', 'Books', 'Movies', 'Football', 'Cricket',
  'Dance', 'Cooking', 'Fitness', 'Yoga', 'Art', 'Gaming', 'Startups', 'Beaches', 'Pets', 'Poetry', 'Food',
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
  final _age = TextEditingController();
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
      _age.text = '${p.age}';
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
    if (_primary == null && _existingPrimary == null && !AppConfig.isDemo) {
      showSnack(context, 'Add a primary photo — it’s the only one strangers see.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(backendProvider).saveProfile(ProfileDraft(
            fullName: _name.text.trim(),
            age: int.parse(_age.text),
            city: _city,
            bio: cleanBio,
            interests: _interests.toList(),
            primaryPhotoWebp: _primary,
            newGalleryWebp: _newGallery,
          ));
      ref.invalidate(myProfileProvider);
      ref.invalidate(feedProvider);
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
    _age.dispose();
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
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.add_a_photo_outlined, size: 40),
                                  ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: const Icon(Icons.edit, size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text('Primary photo · visible on your public card',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _age,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                    decoration: const InputDecoration(labelText: 'Age'),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return (n == null || n < 18) ? '18+ only' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _city,
                    decoration: const InputDecoration(labelText: 'District / City'),
                    items: [
                      for (final c in AppConfig.keralaCities) DropdownMenuItem(value: c, child: Text(c)),
                    ],
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
              decoration: const InputDecoration(
                labelText: 'Bio',
                helperText: 'No phone numbers, @handles or links',
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) => ContactSanitizer.containsContactInfo(v ?? '')
                  ? 'Contact details aren’t allowed in bios'
                  : null,
            ),
            const SizedBox(height: 16),
            _SectionTitle(icon: Icons.lock_outline, text: 'Interests (unlocked after follow)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final i in _allInterests)
                  FilterChip(
                    label: Text(i),
                    selected: _interests.contains(i),
                    onSelected: (s) => setState(() => s ? _interests.add(i) : _interests.remove(i)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _SectionTitle(icon: Icons.lock_outline, text: 'Private photo grid ($galleryCount/9)'),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (final u in _existingGallery)
                  ClipRRect(borderRadius: BorderRadius.circular(10), child: ProfilePhoto(url: u, name: '')),
                for (final b in _newGallery)
                  ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(b, fit: BoxFit.cover)),
                if (galleryCount < 9)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final b = await _pick();
                      if (b != null) setState(() => _newGallery.add(b));
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.add),
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
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: Colors.grey.shade700),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]);
}
