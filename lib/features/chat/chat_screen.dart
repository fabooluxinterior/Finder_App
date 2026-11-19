import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/image_optimizer.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/phosphor.dart';

import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/brand.dart';
import '../../core/feedback.dart';
import '../../core/sanitizer.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/backend.dart';
import '../../data/media_service.dart';
import '../../models/message.dart';
import '../../models/presence.dart';
import '../../models/profile.dart';
import '../../models/profile_catalog.dart';
import '../requests/requests_screen.dart' show IntroQuote;
import '../../providers.dart';
import '../paywall/paywall_sheet.dart';
import '../profile/profile_detail_screen.dart';
import '../safety/safety_actions.dart';
import '../security/safety_number_screen.dart';
import '../../core/view_once_icon.dart';
import 'attach_screen.dart';
import 'emoji_panel.dart';
import 'media_editor_screen.dart';
import 'schedule_picker.dart';
import 'scheduled_messages_screen.dart';
import 'voice_bubble.dart';
import 'voice_recorder_bar.dart';
import 'words.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.peer});
  final PublicProfile peer;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  bool _emojiOpen = false;

  // ------------------------------------------------------------ replies ----
  ChatMessage? _replying;
  String? _highlightId;
  Timer? _highlightTimer;
  final _keys = <String, GlobalKey>{};
  List<ChatMessage> _shown = const [];

  static String _previewOf(ChatMessage m) {
    if (m.deleted) return 'Message deleted';
    if (m.isImage) return (m.content ?? '').trim().isEmpty || m.viewOnce ? 'Photo' : 'Photo · ${m.content!.trim()}';
    if (m.isVoice) return 'Voice message';
    final t = (m.content ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 120 ? '${t.substring(0, 117)}...' : t;
  }

  void _startReply(ChatMessage m) {
    if (m.deleted) return;
    Fx.instance.tap();
    setState(() {
      _replying = m;
      _editing = null;
    });
  }

  ReplyRef? _replyRef() {
    final m = _replying;
    if (m == null) return null;
    return ReplyRef(
      messageId: m.id,
      senderId: m.senderId,
      preview: _previewOf(m),
      kind: m.isImage ? 'photo' : (m.isVoice ? 'voice' : 'text'),
    );
  }

  /// Scrolls to the quoted message (loading it first if it is far away) and highlights it for about a second.
  Future<void> _jumpTo(String id) async {
    final index = _shown.indexWhere((m) => m.id == id);
    if (index < 0) {
      showSnack(context, 'The original message isn’t available.', icon: Icons.info_outline);
      return;
    }
    if (!_scroll.hasClients) return;
    Future<bool> visibleNow() async {
      final ctx = _keys[id]?.currentContext;
      if (ctx == null) return false;
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: Motion.of(context, const Duration(milliseconds: 320)),
        curve: Curves.easeOutCubic,
      );
      return true;
    }

    if (!await visibleNow()) {
      // Not built yet (far away in a long chat): move close using the average message height, then settle on it.
      final perItem = _scroll.position.maxScrollExtent / math.max(1, _shown.length);
      final fromNewest = _shown.length - 1 - index;
      var target = (fromNewest * perItem).clamp(0.0, _scroll.position.maxScrollExtent);
      for (var i = 0; i < 8; i++) {
        if (!mounted) return;
        final d = Motion.of(context, const Duration(milliseconds: 220));
        await _scroll.animateTo(target, duration: d, curve: Curves.easeOutCubic);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        if (await visibleNow()) break;
        target = (target + (i.isEven ? 1 : -1) * perItem * (i + 1)).clamp(0.0, _scroll.position.maxScrollExtent);
      }
    }
    if (!mounted) return;
    _highlightTimer?.cancel();
    setState(() => _highlightId = id);
    _highlightTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  Future<void> _messageInfo(ChatMessage m) async {
    final c = context.fc;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      showDragHandle: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          // Live: the times fill in as the other person's phone reports them.
          final cur =
              (ref.watch(messagesProvider(widget.peer.id)).value ?? const <ChatMessage>[])
                  .where((x) => x.id == m.id)
                  .firstOrNull ??
              m;
          final f = DateFormat('d MMM, h:mm:ss a');
          Widget row(String label, DateTime? at, {String pending = 'Pending', bool blue = false}) => ListTile(
            dense: true,
            leading: Icon(
              at != null ? PhosphorIconsBold.checks : Icons.schedule,
              size: 20,
              color: at != null && blue ? readTickBlue : c.ink2,
            ),
            title: Text(label),
            trailing: Text(at == null ? pending : f.format(at), style: TextStyle(color: at == null ? c.muted : c.ink)),
          );
          final readAt = cur.readAt ?? (cur.isRead ? cur.deliveredAt : null);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'Message info',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                  ),
                  row('Sent', cur.createdAt),
                  row('Delivered', cur.deliveredAt ?? (cur.isRead ? readAt : null)),
                  row('Read', cur.readAt ?? (cur.isRead ? DateTime.fromMillisecondsSinceEpoch(0) : null), blue: true),
                  if (cur.isVoice) row('Listened', cur.listenedAt, pending: 'Not played yet', blue: true),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ------------------------------------------------ jump to the latest message ----
  bool _showLatest = false;

  void _onScrolled() {
    if (!_scroll.hasClients) return;
    final away = _scroll.offset > 320; // the list is reversed: 0 is the newest message
    if (away != _showLatest) setState(() => _showLatest = away);
  }

  Widget _latestButton(FinderColors c) => Positioned(
    left: 0,
    right: 0,
    bottom: 2,
    child: IgnorePointer(
      ignoring: !_showLatest,
      child: AnimatedOpacity(
        opacity: _showLatest ? 1 : 0,
        duration: Motion.of(context, Motion.fast),
        child: Center(
          child: IconButton(
            tooltip: 'Latest messages',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
            onPressed: () {
              if (_scroll.hasClients) {
                _scroll.animateTo(0, duration: Motion.of(context, const Duration(milliseconds: 260)), curve: Curves.easeOutCubic);
              }
            },
            icon: Icon(Icons.keyboard_arrow_down_rounded, size: 30, color: c.ink2),
          ),
        ),
      ),
    ),
  );

  // ------------------------------------------------ disappearing messages ----
  Disappearing _dis = Disappearing.off;
  Timer? _disTimer;

  Future<void> _refreshDisappearing() async {
    try {
      final d = await _backend.disappearing(widget.peer.id);
      if (!mounted) return;
      final me = _backend.currentUserId;
      if (d != _dis && d.setBy != null && d.setBy != me) {
        showSnack(
          context,
          d.on
              ? '${widget.peer.firstName} set messages to disappear after ${Disappearing.label(d.seconds)}.'
              : '${widget.peer.firstName} turned off disappearing messages.',
          icon: Icons.timer_outlined,
        );
      }
      if (d.on) await _backend.purgeExpired(widget.peer.id);
      if (mounted) setState(() => _dis = d);
    } catch (_) {
      if (mounted) setState(() {}); // still hide anything that has expired
    }
  }

  List<ChatMessage> _visible(List<ChatMessage> l) {
    if (!_dis.on) return l;
    final now = DateTime.now();
    return [
      for (final m in l)
        if (!_dis.expired(m, now)) m,
    ];
  }

  Future<void> _chooseDisappearing() async {
    final c = context.fc;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: c.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Disappearing messages',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.ink),
              ),
              const SizedBox(height: 6),
              Text(
                'New messages in this chat disappear for both of you after the time you choose. Messages sent before you turn it on stay.',
                style: TextStyle(fontSize: 14.5, height: 1.4, color: c.ink3),
              ),
              const SizedBox(height: 8),
              for (final s in [86400, 604800, 2592000, 0])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(Disappearing.label(s)),
                  trailing: _dis.seconds == s ? Icon(PhosphorIconsFill.checkCircle, color: c.accent) : null,
                  onTap: () => Navigator.pop(ctx, s),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == _dis.seconds || !mounted) return;
    try {
      await _backend.setDisappearing(widget.peer.id, picked);
      await _refreshDisappearing();
      if (mounted) {
        showSnack(
          context,
          picked == 0 ? 'Disappearing messages are off.' : 'Messages will disappear after ${Disappearing.label(picked)}.',
          icon: Icons.timer_outlined,
        );
      }
    } catch (e) {
      await _handleError(e);
    }
  }

  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = VoiceRecorder();
  bool _recording = false;
  bool _sending = false;

  /// Messages picked (long-press) to report as evidence.
  final _selected = <String>{};

  /// Messages present when the thread opened don't animate; new ones do.
  Set<String>? _initialIds;

  /// The message being edited (the composer holds its text until sent or cancelled).
  ChatMessage? _editing;

  /// "online" / "last seen …" for the other person, refreshed while this chat is open.
  DateTime? _lastActive;
  Timer? _presenceTimer;
  bool _markingRead = false;

  @override
  void initState() {
    super.initState();
    // No alert for messages in the chat that is already open.
    WidgetsBinding.instance.addObserver(this);
    _openChat = ref.read(openChatProvider.notifier);
    _backend = ref.read(backendProvider);
    _text.addListener(_onTextChanged);
    _scroll.addListener(_onScrolled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openChat.open(widget.peer.id);
    });
    _refreshPresence();
    // Instant: the server pushes every change of their online / last seen while this chat is open.
    _presenceSub = _backend.watchPeerPresence(widget.peer.id).listen((p) {
      if (!mounted) return;
      if (p?.lastActive != _lastActive || (p?.online ?? false) != _online) {
        setState(() {
          _lastActive = p?.lastActive;
          _online = p?.online ?? false;
        });
      }
    }, onError: (_) {});
    // Safety net (e.g. an app that was killed without saying goodbye stops being online after 90 s).
    _presenceTimer = Timer.periodic(const Duration(seconds: 10), (_) => _refreshPresence());
    _refreshDisappearing();
    _syncScheduled();
    _disTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _refreshDisappearing();
      _syncScheduled();
    });
  }

  bool _online = false;
  StreamSubscription<PeerPresence?>? _presenceSub;

  Future<void> _refreshPresence() async {
    final p = await _backend.peerPresence(widget.peer.id);
    if (!mounted) return;
    if (p?.lastActive != _lastActive || (p?.online ?? false) != _online) {
      setState(() {
        _lastActive = p?.lastActive;
        _online = p?.online ?? false;
      });
    }
  }

  /// True only while the app is in front. A locked screen or another app counts as away: nothing is read then.
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      // Back in front: this chat is open again, and what arrived meanwhile is read now.
      _openChat.open(widget.peer.id);
      _refreshPresence();
      _markReadIfNeeded(_shown, _backend.currentUserId);
    } else {
      // Away: alerts for this chat must work again, and the other person stops seeing "typing…".
      _openChat.closeIf(widget.peer.id);
      _typingIdle?.cancel();
      if (_mine != PeerState.idle) _setMine(PeerState.idle);
    }
  }

  /// "online" while the other person is in the app, otherwise "last seen …".
  String? get _presenceText {
    final t = _lastActive;
    if (t == null) return null;
    if (_online) return 'online';
    final time = DateFormat('h:mm a').format(t);
    if (DateUtils.isSameDay(t, DateTime.now())) return 'last seen today at $time';
    if (DateUtils.isSameDay(t, DateTime.now().subtract(const Duration(days: 1)))) return 'last seen yesterday at $time';
    return 'last seen ${DateFormat('d MMM').format(t)}';
  }

  /// Opening a chat marks everything in it as read (once per change; never loops).
  void _markReadIfNeeded(List<ChatMessage> list, String? me) {
    if (!_foreground || _markingRead || !list.any((m) => m.receiverId == me && !m.isRead)) return;
    _markingRead = true;
    _backend.markThreadRead(widget.peer.id).catchError((_) {}).whenComplete(() => _markingRead = false);
  }

  // ------------------------------------------- what the other person sees ----
  // Typing, recording audio and sending a photo are shared as small live signals
  // (private to this chat, never stored). They repeat every 2.5 s while they last.
  late final FinderBackend _backend;
  PeerState _mine = PeerState.idle;
  Timer? _heartbeat;
  Timer? _typingIdle;

  bool get _sharing => ref.read(sharePresenceProvider).value ?? true;

  void _setMine(PeerState s) {
    _heartbeat?.cancel();
    if (!_sharing) return;
    final changed = s != _mine;
    _mine = s;
    if (s == PeerState.idle) {
      if (changed) _backend.sendPeerState(widget.peer.id, s);
      return;
    }
    _backend.sendPeerState(widget.peer.id, s);
    if (s != PeerState.photo) {
      _heartbeat = Timer.periodic(presenceRefresh, (_) => _backend.sendPeerState(widget.peer.id, s));
    }
  }

  void _onTextChanged() {
    if (_recording) return;
    if (_text.text.trim().isEmpty) {
      _typingIdle?.cancel();
      if (_mine == PeerState.typing) _setMine(PeerState.idle);
      return;
    }
    if (_mine != PeerState.typing) _setMine(PeerState.typing);
    // Stopped typing without sending: say so after 4 s (the other side also clears it by itself).
    _typingIdle?.cancel();
    _typingIdle = Timer(const Duration(seconds: 4), () {
      if (_mine == PeerState.typing) _setMine(PeerState.idle);
    });
  }

  late final OpenChatNotifier _openChat;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final open = _openChat;
    final id = widget.peer.id;
    Future.microtask(() => open.closeIf(id));
    _heartbeat?.cancel();
    _typingIdle?.cancel();
    _presenceTimer?.cancel();
    _presenceSub?.cancel();
    _disTimer?.cancel();
    _highlightTimer?.cancel();
    // _mine only leaves idle while sharing is on (see _setMine), so no provider read is needed here.
    if (_mine != PeerState.idle) _backend.sendPeerState(id, PeerState.idle);
    _text.removeListener(_onTextChanged);
    _text.dispose();
    _scroll.removeListener(_onScrolled);
    _scroll.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: Motion.of(context, Motion.medium), curve: Motion.easeOut);
  }

  /// Sending needs Fast-Track; the server enforces it, the app explains it.
  Future<bool> _handleError(Object e) async {
    if (!mounted) return false;
    if (e is AppException && e.code == AppErrorCode.subscriptionRequired) {
      return showPaywall(context, reason: PaywallReason.messaging);
    }
    showSnack(context, '$e', icon: PhosphorIconsFill.warningCircle);
    return false;
  }

  // ------------------------------------------------------ scheduled messages ----
  // Scheduled messages live on the server and are released at their time, even when this phone is off. They are
  // not shown in the chat until then; they are listed in "Scheduled messages" in this chat's menu.

  /// Puts messages the server has already sent into this chat (and keeps the list fresh).
  Future<void> _syncScheduled() async {
    try {
      await _backend.scheduledMessages(peerId: widget.peer.id);
    } catch (_) {
      /* offline: nothing to show yet */
    }
  }

  Future<void> _scheduleText(List<ChatMessage> thread) async {
    final me = _backend.currentUserId;
    var text = _text.text.trim();
    if (text.isEmpty || _editing != null) return;
    if (!isPremium(ref)) {
      await showPaywall(context, reason: PaywallReason.messaging);
      return;
    }
    final sentByMe = thread.where((m) => m.senderId == me).length;
    if (sentByMe < AppConfig.sanitizedOpeningMessages && ContactSanitizer.containsContactInfo(text)) {
      text = ContactSanitizer.sanitize(text);
      showSnack(context, 'Contact details were removed. Get to know each other first.', icon: PhosphorIconsFill.shieldCheck);
      if (text.replaceAll('•', '').trim().isEmpty) return;
    }
    final at = await pickSendTime(context);
    if (at == null || !mounted) return;
    try {
      await _backend.scheduleMessage(widget.peer.id, text, at);
      _text.clear();
      Fx.instance.tap();
      if (mounted) showSnack(context, 'Scheduled for ${DateFormat('d MMM, h:mm a').format(at)}.', icon: Icons.schedule);
    } catch (e) {
      await _handleError(e);
    }
  }

  void _insertEmoji(String e) {
    final v = _text.value;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    final next = v.text.replaceRange(sel.start, sel.end, e);
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: sel.start + e.length),
    );
  }

  void _emojiBackspace() {
    final v = _text.value;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    if (sel.start != sel.end) {
      _text.value = TextEditingValue(
        text: v.text.replaceRange(sel.start, sel.end, ''),
        selection: TextSelection.collapsed(offset: sel.start),
      );
    } else if (sel.start > 0) {
      final before = v.text.substring(0, sel.start).characters.skipLast(1).toString();
      _text.value = TextEditingValue(
        text: before + v.text.substring(sel.start),
        selection: TextSelection.collapsed(offset: before.length),
      );
    }
  }

  void _toggleEmoji() {
    FocusScope.of(context).unfocus();
    setState(() => _emojiOpen = !_emojiOpen);
  }

  Future<void> _sendText(List<ChatMessage> thread) async {
    final me = ref.read(backendProvider).currentUserId;
    var text = _text.text.trim();
    if (text.isEmpty) return;

    // Opening messages are filtered for phone numbers, @handles and links.
    final sentByMe = thread.where((m) => m.senderId == me).length;
    if (sentByMe < AppConfig.sanitizedOpeningMessages && ContactSanitizer.containsContactInfo(text)) {
      text = ContactSanitizer.sanitize(text);
      showSnack(context, 'Contact details were removed. Get to know each other first.', icon: PhosphorIconsFill.shieldCheck);
      if (text.replaceAll('•', '').trim().isEmpty) return;
    }

    setState(() => _sending = true);
    try {
      _setMine(PeerState.idle);
      final editing = _editing;
      if (editing != null) {
        if (ContactSanitizer.containsContactInfo(text) &&
            thread.where((m) => m.senderId == me).length <= AppConfig.sanitizedOpeningMessages) {
          showSnack(
            context,
            'Contact details can’t be added yet. Get to know each other first.',
            icon: PhosphorIconsFill.shieldCheck,
          );
          return;
        }
        if (text != (editing.content ?? '').trim()) {
          await ref.read(backendProvider).editMessage(widget.peer.id, editing.id, text);
          Fx.instance.sent();
        }
        if (mounted) setState(() => _editing = null);
      } else {
        await ref.read(backendProvider).sendText(widget.peer.id, text, replyTo: _replyRef());
        if (mounted) setState(() => _replying = null);
        Fx.instance.sent();
        _scrollToLatest();
      }
      _text.clear();
    } catch (e) {
      await _handleError(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startRecording() async {
    if (!isPremium(ref)) {
      await showPaywall(context, reason: PaywallReason.messaging);
      return;
    }
    if (!await _recorder.hasPermission()) {
      if (mounted) showSnack(context, 'Allow microphone access to send voice notes.', icon: PhosphorIconsFill.microphoneSlash);
      return;
    }
    try {
      // The bar owns the 45 second limit and moves to review when it is reached.
      await _recorder.start(onCapReached: () {});
      Fx.instance.tap();
      setState(() => _recording = true);
    } catch (e) {
      if (mounted) showSnack(context, 'Couldn’t start recording.', icon: PhosphorIconsFill.microphoneSlash);
    }
  }

  /// The bar reports whether the microphone is open (recording or hands-free).
  void _recordingActive(bool active) {
    if (!mounted) return;
    _setMine(active ? PeerState.recording : PeerState.idle);
  }

  void _voiceCancelled() {
    if (mounted) setState(() => _recording = false);
  }

  void _voiceTooShort() {
    if (!mounted) return;
    setState(() => _recording = false);
    _recorder.cancel();
    showSnack(context, 'Hold a little longer to record a voice note.');
  }

  Future<void> _sendVoice(VoiceNote note) async {
    if (!mounted) return;
    setState(() {
      _recording = false;
      _sending = true;
    });
    try {
      await ref.read(backendProvider).sendVoice(widget.peer.id, note.bytes, localPath: note.path, duration: note.duration);
      Fx.instance.sent();
      _scrollToLatest();
    } catch (e) {
      await _handleError(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendPhoto() async {
    if (!isPremium(ref)) {
      await showPaywall(context, reason: PaywallReason.messaging);
      return;
    }
    try {
      // The camera with your latest pictures underneath (swipe up for the whole gallery).
      final picked = await Navigator.push<AttachResult>(
        context,
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const AttachScreen()),
      );
      if (picked == null || !mounted) return;
      var photos = picked.photos;
      if (picked.useSystemPicker) {
        // Camera or gallery access was refused: the phone's own picker still works.
        final raw = await ref.read(mediaProvider).pickOriginalPhoto();
        if (raw == null || !mounted) return;
        photos = [raw];
      }
      for (var i = 0; i < photos.length; i++) {
        if (!mounted) return;
        // Preview first: crop, add text or draw, then send (View once only for a single photo).
        final edited = await Navigator.push<EditedMedia>(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => MediaEditorScreen(
              bytes: photos[i],
              allowSchedule: false,
              allowOnce: photos.length == 1,
              positionLabel: photos.length > 1 ? '${i + 1} of ${photos.length}' : null,
            ),
          ),
        );
        if (edited == null || !mounted) return; // cancelled: stop here
        setState(() => _sending = true);
        // Any image type: resized and compressed on the device, then encrypted.
        final img = await ImageOptimizer.optimizeForChat(edited.bytes);
        _setMine(PeerState.photo);
        await ref
            .read(backendProvider)
            .sendImage(
              widget.peer.id,
              img.bytes,
              width: img.width,
              height: img.height,
              once: edited.once,
              caption: edited.caption,
            );
        Fx.instance.sent();
        _scrollToLatest();
      }
    } catch (e) {
      await _handleError(e);
    } finally {
      _setMine(PeerState.idle);
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startEdit(ChatMessage m) {
    setState(() {
      _editing = m;
      _replying = null;
    });
    _text.text = m.content ?? '';
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
  }

  void _cancelEdit() {
    setState(() => _editing = null);
    _text.clear();
  }

  Future<void> _deleteMessage(ChatMessage m) async {
    final c = context.fc;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: c.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delete this message?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.ink),
              ),
              const SizedBox(height: 6),
              Text(
                'It is removed for both of you. ${widget.peer.firstName} will only see that a message was deleted.',
                style: TextStyle(fontSize: 14.5, height: 1.4, color: c.ink3),
              ),
              const SizedBox(height: 16),
              PillButton(label: 'Delete for everyone', onTap: () => Navigator.pop(ctx, true)),
              const SizedBox(height: 8),
              Center(
                child: TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(backendProvider).deleteMessage(widget.peer.id, m.id);
      Fx.instance.tap();
    } catch (e) {
      await _handleError(e);
    }
  }

  /// Long-press: your own messages can be edited or deleted; anyone's can be picked to report.
  Future<void> _messageActions(ChatMessage m, bool mine) async {
    if (m.deleted) return;
    Fx.instance.tap();
    final c = context.fc;
    final canEdit = mine && m.content != null && !m.isVoice && !m.isImage;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.reply_rounded, color: c.ink2),
              title: const Text('Reply'),
              onTap: () => Navigator.pop(ctx, 'reply'),
            ),
            if (mine)
              ListTile(
                leading: Icon(Icons.info_outline, color: c.ink2),
                title: const Text('Message info'),
                onTap: () => Navigator.pop(ctx, 'info'),
              ),
            if (canEdit)
              ListTile(
                leading: Icon(Icons.edit_outlined, color: c.ink2),
                title: const Text('Edit'),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
            if (mine)
              ListTile(
                leading: Icon(PhosphorIconsRegular.trash, color: c.accent),
                title: Text('Delete for everyone', style: TextStyle(color: c.accent)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ListTile(
              leading: Icon(PhosphorIconsRegular.flag, color: c.ink2),
              title: const Text('Select to report'),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'reply':
        _startReply(m);
      case 'info':
        await _messageInfo(m);
      case 'edit':
        _startEdit(m);
      case 'delete':
        await _deleteMessage(m);
      case 'report':
        _toggle(m);
    }
  }

  void _toggle(ChatMessage m) => setState(() => _selected.contains(m.id) ? _selected.remove(m.id) : _selected.add(m.id));

  Future<void> _reportSelected(List<ChatMessage> thread) async {
    final picked = thread.where((m) => _selected.contains(m.id)).toList();
    final sent = await showReportSheet(context, widget.peer, thread: thread, selected: picked);
    if (!mounted) return;
    setState(_selected.clear);
    if (sent) Navigator.pop(context);
  }

  void _openProfile() => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileDetailScreen(profile: widget.peer)));

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final backend = ref.watch(backendProvider);
    final me = backend.currentUserId;
    final visibleMessages = ref.watch(messagesProvider(widget.peer.id)).whenData(_visible);
    final messages = visibleMessages;
    final theirState = ref.watch(peerStateProvider(widget.peer.id)).value ?? PeerState.idle;

    ref.listen(messagesProvider(widget.peer.id), (prev, next) {
      final list = next.value ?? const <ChatMessage>[];
      _markReadIfNeeded(list, me);
      final before = prev?.value ?? const <ChatMessage>[];
      if (before.isNotEmpty && list.length > before.length && list.last.senderId != me && _foreground) Fx.instance.received();
      if (before.length < list.length) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
    });

    final thread = visibleMessages.value ?? const <ChatMessage>[];
    _shown = thread;
    if (_initialIds == null && messages.hasValue) _initialIds = thread.map((m) => m.id).toSet();
    // ref.listen only fires on changes, so messages that were already waiting are marked read here.
    if (messages.hasValue) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _markReadIfNeeded(thread, me) : null);

    final conn = ref.watch(connectionsProvider).value?.where((x) => x.profile.id == widget.peer.id).firstOrNull;
    final intro = conn?.introText == null
        ? null
        : IntroQuote(
            question: promptById(conn!.introPromptId ?? '')?.question,
            text: conn.introText!,
            label: conn.introFromMe ? 'You replied to their prompt' : '${widget.peer.firstName} replied to your prompt',
            note: 'Sent with the request, before this chat was encrypted.',
          );
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: SafeArea(
          bottom: false,
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: VIcon(VIcons.back, size: 24, color: c.ink),
                  tooltip: 'Back',
                ),
                Expanded(
                  child: Pressable(
                    scale: 0.98,
                    haptic: false,
                    onTap: _openProfile,
                    child: Row(
                      children: [
                        Avatar(url: widget.peer.primaryPhoto, name: widget.peer.fullName, size: 44),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      widget.peer.firstName,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w600, color: c.ink),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  if (widget.peer.isVerified) const VerifiedBadge(size: 16),
                                ],
                              ),
                              // What they are doing uses the same quiet words with a sweeping light as the line
                              // under the messages; otherwise online / last seen.
                              AnimatedSwitcher(
                                duration: Motion.of(context, const Duration(milliseconds: 180)),
                                transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
                                layoutBuilder: (current, previous) =>
                                    Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                                child: theirState != PeerState.idle
                                    ? SizedBox(
                                        key: ValueKey(theirState),
                                        height: 18,
                                        child: WordsLine(words: theirState.words, size: 13, color: c.accent),
                                      )
                                    : Text(
                                        _presenceText ?? widget.peer.city,
                                        key: const ValueKey('presence'),
                                        style: TextStyle(
                                          fontSize: 13,
                                          height: 18 / 13,
                                          color: _presenceText == 'online' ? c.accent : c.muted,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: VIcon(VIcons.more, size: 24, color: c.ink),
                  color: c.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  onSelected: (v) async {
                    switch (v) {
                      case 'scheduled':
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ScheduledMessagesScreen(peer: widget.peer)));
                      case 'disappearing':
                        _chooseDisappearing();
                      case 'verify':
                        Navigator.push(context, MaterialPageRoute(builder: (_) => SafetyNumberScreen(peer: widget.peer)));
                      case 'report':
                        if (await showReportSheet(context, widget.peer, thread: thread) && context.mounted) {
                          Navigator.pop(context);
                        }
                      case 'block':
                        if (await confirmBlock(context, ref, widget.peer) && context.mounted) Navigator.pop(context);
                      case 'unmatch':
                        if (await confirmUnmatch(context, ref, widget.peer) && context.mounted) Navigator.pop(context);
                    }
                  },
                  itemBuilder: (_) => [
                    _menuItem('scheduled', Icons.schedule, 'Scheduled messages'),
                    _menuItem('disappearing', Icons.timer_outlined, 'Disappearing messages'),
                    if (backend.isEndToEndEncrypted) _menuItem('verify', PhosphorIconsRegular.shieldCheck, 'Verify encryption'),
                    _menuItem('report', PhosphorIconsRegular.flag, 'Report'),
                    _menuItem('block', PhosphorIconsRegular.prohibit, 'Block'),
                    _menuItem('unmatch', PhosphorIconsRegular.userMinus, 'Unmatch'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: messages.when(
                    skipLoadingOnReload: true,
                    loading: () => const SizedBox.shrink(),
                    error: (e, _) => Center(child: Text('$e')),
                    data: (list) => list.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              _ThreadIntro(peer: widget.peer, encrypted: backend.isEndToEndEncrypted),
                              ?intro,
                            ],
                          )
                        : ListView.builder(
                            controller: _scroll,
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            itemCount: list.length + 1,
                            itemBuilder: (_, i) {
                              if (i == list.length) {
                                return Column(
                                  children: [
                                    _PrivacyPill(encrypted: backend.isEndToEndEncrypted),
                                    if (intro != null) Padding(padding: const EdgeInsets.only(top: 8), child: intro),
                                  ],
                                );
                              }
                              final m = list[list.length - 1 - i];
                              final older = i + 1 < list.length ? list[list.length - 2 - i] : null;
                              final newer = i > 0 ? list[list.length - i] : null;
                              final showDay = older == null || !DateUtils.isSameDay(older.createdAt, m.createdAt);
                              final mine = m.senderId == me;
                              // Group consecutive bubbles from the same sender.
                              final tail = newer == null || newer.senderId != m.senderId;
                              final picked = _selected.contains(m.id);
                              final bubble = GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onLongPress: () => _selected.isEmpty ? _messageActions(m, mine) : _toggle(m),
                                onTap: _selected.isEmpty ? null : () => _toggle(m),
                                child: AnimatedContainer(
                                  duration: Motion.of(context, Motion.fast),
                                  decoration: BoxDecoration(
                                    color: picked
                                        ? c.accent.withValues(alpha: 0.16)
                                        : (_highlightId == m.id ? c.accent.withValues(alpha: 0.24) : Colors.transparent),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: _Bubble(
                                    message: m,
                                    mine: mine,
                                    tail: tail,
                                    selecting: _selected.isNotEmpty,
                                    meId: me ?? '',
                                    peerName: widget.peer.firstName,
                                    onQuoteTap: (id) => _jumpTo(id),
                                  ),
                                ),
                              );
                              final swipable = _SwipeToReply(
                                enabled: !m.deleted && _selected.isEmpty,
                                onReply: () => _startReply(m),
                                child: bubble,
                              );
                              return Column(
                                key: _keys.putIfAbsent(m.id, GlobalKey.new),
                                children: [
                                  if (showDay) _DayChip(m.createdAt),
                                  _initialIds?.contains(m.id) ?? true
                                      ? swipable
                                      : _Arrive(key: ValueKey(m.id), mine: mine, child: swipable),
                                ],
                              );
                            },
                          ),
                  ),
                ),
                _latestButton(c),
              ],
            ),
          ),
          if (_dis.on)
            GestureDetector(
              onTap: _chooseDisappearing,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timer_outlined, size: 14, color: c.muted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Messages disappear after ${Disappearing.label(_dis.seconds)}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: c.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          PeerStateLine(state: theirState),
          SafeArea(
            top: false,
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.fast),
              switchInCurve: Motion.easeOut,
              child: _selected.isNotEmpty
                  ? _SelectionBar(
                      key: const ValueKey('select'),
                      count: _selected.length,
                      onCancel: () => setState(_selected.clear),
                      onReport: () => _reportSelected(thread),
                    )
                  : _recording
                  ? VoiceRecorderBar(
                      key: const ValueKey('rec'),
                      recorder: _recorder,
                      onCancel: _voiceCancelled,
                      onSend: _sendVoice,
                      onTooShort: _voiceTooShort,
                      onActive: _recordingActive,
                    )
                  : Column(
                      key: const ValueKey('compose'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_editing != null)
                          Container(
                            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: c.hair),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 16, color: c.accent),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Editing message',
                                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.ink2),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _cancelEdit,
                                  tooltip: 'Cancel edit',
                                  icon: Icon(PhosphorIconsRegular.x, size: 18, color: c.muted),
                                ),
                              ],
                            ),
                          ),
                        if (_replying != null)
                          _ReplyBar(
                            name: _replying!.senderId == me ? 'You' : widget.peer.firstName,
                            preview: _previewOf(_replying!),
                            onClose: () => setState(() => _replying = null),
                          ),
                        _Composer(
                          controller: _text,
                          sending: _sending,
                          editing: _editing != null,
                          onSend: () => _sendText(thread),
                          onMic: _startRecording,
                          onPhoto: _sendPhoto,
                          emojiOpen: _emojiOpen,
                          onEmoji: _toggleEmoji,
                          onSchedule: () => _scheduleText(thread),
                          onFieldTap: () {
                            if (_emojiOpen) setState(() => _emojiOpen = false);
                          },
                        ),
                        if (_emojiOpen) EmojiPanel(onPick: _insertEmoji, onBackspace: _emojiBackspace),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) => PopupMenuItem(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18, color: context.fc.ink2),
        const SizedBox(width: 10),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

/// A new message eases in from its own side: 10 px sideways and 4 px up, a faint fade (160 ms).
/// Kept deliberately small so a busy chat stays calm; skipped when the phone reduces motion.
class _Arrive extends StatelessWidget {
  const _Arrive({super.key, required this.child, required this.mine});
  final Widget child;
  final bool mine;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Motion.of(context, const Duration(milliseconds: 160)),
    curve: Curves.easeOutCubic,
    builder: (_, v, child) => Opacity(
      opacity: 0.2 + 0.8 * v,
      child: Transform.translate(offset: Offset((mine ? 10 : -10) * (1 - v), 4 * (1 - v)), child: child),
    ),
    child: child,
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onMic,
    required this.onPhoto,
    required this.onEmoji,
    required this.onFieldTap,
    required this.onSchedule,
    this.emojiOpen = false,
    this.editing = false,
  });
  final VoidCallback onEmoji;
  final VoidCallback onSchedule;
  final VoidCallback onFieldTap;
  final bool emojiOpen;
  final bool editing;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onMic;
  final VoidCallback onPhoto;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, value, _) {
          final hasText = editing || value.text.trim().isNotEmpty;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  style: t.bodyLarge?.copyWith(color: c.ink),
                  onTap: onFieldTap,
                  decoration: InputDecoration(
                    hintText: 'Message',
                    counterText: '',
                    // Emoji on the left of the bar, photo on the right.
                    prefixIcon: IconButton(
                      onPressed: sending ? null : onEmoji,
                      tooltip: emojiOpen ? 'Keyboard' : 'Emoji',
                      icon: Icon(
                        emojiOpen ? Icons.keyboard_alt_outlined : Icons.emoji_emotions_outlined,
                        size: 24,
                        color: c.ink2,
                      ),
                    ),
                    suffixIcon: IconButton(
                      onPressed: sending || editing ? null : onPhoto,
                      tooltip: 'Attach',
                      icon: Icon(Icons.attach_file_rounded, size: 22, color: c.ink2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 15),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(26),
                      borderSide: BorderSide(color: c.hair),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(26),
                      borderSide: BorderSide(color: c.hair),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(26),
                      borderSide: BorderSide(color: c.ink3),
                    ),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                // Hold the send button to choose when it is sent.
                onLongPress: sending || !hasText || editing ? null : onSchedule,
                child: Pressable(
                  onTap: sending ? null : (hasText ? onSend : onMic),
                  semanticLabel: hasText ? 'Send' : 'Record voice note',
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                    // Mic ↔ send morph: scale + blur crossfade.
                    child: AnimatedSwitcher(
                      duration: Motion.of(context, Motion.fast),
                      switchInCurve: Motion.easeOut,
                      switchOutCurve: Motion.easeOut,
                      transitionBuilder: (child, a) => ScaleTransition(
                        scale: Tween(begin: 0.6, end: 1.0).animate(a),
                        child: FadeTransition(
                          opacity: a,
                          child: AnimatedBuilder(
                            animation: a,
                            builder: (_, child) => ImageFiltered(
                              imageFilter: ImageFilter.blur(sigmaX: (1 - a.value) * 3, sigmaY: (1 - a.value) * 3),
                              child: child,
                            ),
                            child: child,
                          ),
                        ),
                      ),
                      child: sending
                          ? SizedBox(
                              key: const ValueKey('s'),
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: c.paper),
                            )
                          : VIcon(hasText ? VIcons.send : VIcons.voice, key: ValueKey(hasText), size: 22, color: c.paper),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Blue for "read".
const readTickBlue = Color(0xFF4FC3F7);

const _pict =
    r'[\u{1F000}-\u{1FAFF}\u{2190}-\u{21FF}\u{2300}-\u{23FF}\u{2600}-\u{27BF}\u{2900}-\u{297F}\u{2B00}-\u{2BFF}\u{00A9}\u{00AE}\u{203C}\u{2049}\u{2122}\u{2139}\u{3030}\u{303D}\u{3297}\u{3299}]';
final _emojiRun = RegExp(
  '^(?:$_pict|[\\u{1F1E6}-\\u{1F1FF}]{2}|[#*0-9]\\uFE0F?\\u20E3)[\\u{1F3FB}-\\u{1F3FF}\\uFE0F]*(?:\\u200D$_pict[\\u{1F3FB}-\\u{1F3FF}\\uFE0F]*)*\$',
  unicode: true,
);

/// True for a message that is exactly one emoji (including flags, skin tones and joined emoji).
bool isSingleEmoji(String? text) {
  final t = text?.trim();
  if (t == null || t.isEmpty || t.characters.length != 1) return false;
  return _emojiRun.hasMatch(t);
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.tail,
    this.selecting = false,
    this.meId = '',
    this.peerName = '',
    this.onQuoteTap,
  });
  final String meId;
  final String peerName;
  final ValueChanged<String>? onQuoteTap;
  final ChatMessage message;
  final bool mine;
  final bool tail;

  /// While picking messages to report, a tap selects instead of opening.
  final bool selecting;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final time = DateFormat('h:mm a').format(message.createdAt);
    final fg = mine ? c.onSent : c.ink;
    final meta = mine ? c.onSent.withValues(alpha: 0.7) : c.muted;
    if (message.deleted) {
      // Nothing of the original is kept: a dim line in its place.
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(top: 3, bottom: tail ? 7 : 2),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: c.hair),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsRegular.prohibit, size: 14, color: c.muted.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text(
                'Message deleted',
                style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: c.muted.withValues(alpha: 0.75)),
              ),
              const SizedBox(width: 8),
              Text(
                time,
                style: TextStyle(fontFamily: 'Geist', color: c.muted.withValues(alpha: 0.6), fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
        child: Container(
          margin: EdgeInsets.only(top: 3, bottom: tail ? 7 : 2),
          padding: message.isImage ? const EdgeInsets.fromLTRB(4, 4, 10, 6) : const EdgeInsets.fromLTRB(15, 11, 13, 8),
          decoration: BoxDecoration(
            color: mine ? c.sentBubble : c.surface,
            border: mine ? null : Border.all(color: c.hair),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: Radius.circular(!mine && tail ? 6 : 22),
              bottomRight: Radius.circular(mine && tail ? 6 : 22),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.replyTo != null)
                _Quote(
                  reply: message.replyTo!,
                  name: message.replyTo!.senderId == meId ? 'You' : peerName,
                  mine: mine,
                  onTap: onQuoteTap == null ? null : () => onQuoteTap!(message.replyTo!.messageId),
                ),
              if (message.viewOnce)
                _OnceTile(
                  message: message,
                  mine: mine,
                  peerId: mine ? message.receiverId : message.senderId,
                  color: fg,
                  openable: !selecting,
                )
              else if (message.isImage) ...[
                _PhotoContent(message: message, openable: !selecting),
                if ((message.content ?? '').trim().isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 2, 0),
                      child: Text(
                        message.content!.trim(),
                        style: TextStyle(fontFamily: 'Geist', color: fg, fontSize: 16, height: 22 / 16),
                      ),
                    ),
                  ),
              ] else if (message.isVoice)
                VoiceBubble(message: message, color: fg)
              else
                Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: Text(
                    message.content ?? '',
                    // One emoji on its own is shown a little larger; anything else keeps the normal size.
                    style: isSingleEmoji(message.content)
                        ? TextStyle(fontSize: 38, height: 1.2, color: fg)
                        : TextStyle(fontFamily: 'Geist', color: fg, fontSize: 16, height: 22 / 16),
                  ),
                ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.edited) ...[
                    Text(
                      'edited',
                      style: TextStyle(fontFamily: 'Geist', color: meta, fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    time,
                    style: TextStyle(fontFamily: 'Geist', color: meta, fontSize: 11),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 3),
                    // One grey tick: sent. Two grey ticks: delivered. Two blue ticks: read.
                    Icon(
                      message.receipt == ReceiptStatus.sent ? PhosphorIconsBold.check : PhosphorIconsBold.checks,
                      size: 14,
                      color: message.receipt == ReceiptStatus.read ? readTickBlue : meta,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// End-to-end encrypted photo: downloaded and decrypted on this device.
class _PhotoContent extends ConsumerStatefulWidget {
  const _PhotoContent({required this.message, this.openable = true});
  final ChatMessage message;
  final bool openable;

  @override
  ConsumerState<_PhotoContent> createState() => _PhotoContentState();
}

class _PhotoContentState extends ConsumerState<_PhotoContent> {
  // Fetched and decrypted once per bubble, so rebuilds never reload or flash the photo.
  late final Future<Uint8List> _future = ref.read(backendProvider).imageBytes(widget.message);

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final openable = widget.openable;
    final c = context.fc;
    final img = message.image;
    final ratio = img != null && img.width > 0 && img.height > 0 ? img.width / img.height : 4 / 5;
    return Semantics(
      image: true,
      label: 'Photo',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 220,
          child: AspectRatio(
            aspectRatio: ratio.clamp(0.6, 1.6),
            child: FutureBuilder(
              future: _future,
              builder: (context, s) {
                if (s.hasError) {
                  return ColoredBox(
                    color: c.hair,
                    child: Center(child: Icon(PhosphorIconsRegular.imageBroken, color: c.muted)),
                  );
                }
                if (!s.hasData) {
                  return ColoredBox(
                    color: c.hair,
                    child: const Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                  );
                }
                return GestureDetector(
                  onTap: !openable ? null : () => Navigator.push(context, chatPhotoRoute(s.data!)),
                  child: Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens a photo full screen with a quick fade.
Route<void> chatPhotoRoute(Uint8List bytes, {bool once = false}) {
  // No keyboard coming back when the photo closes (it would resize the chat under it).
  FocusManager.instance.primaryFocus?.unfocus();
  return _chatPhotoRoute(bytes, once: once);
}

Route<void> _chatPhotoRoute(Uint8List bytes, {bool once = false}) => PageRouteBuilder<void>(
  opaque: false,
  barrierColor: Colors.transparent,
  transitionDuration: const Duration(milliseconds: 140),
  reverseTransitionDuration: const Duration(milliseconds: 110),
  pageBuilder: (_, _, _) => ChatPhotoViewer(bytes: bytes, once: once),
  transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
);

/// True when a vertical drag of [dy] pixels, released at [velocity] pixels per second, should close the viewer.
@visibleForTesting
bool shouldDismissPhoto(double dy, double velocity) => dy.abs() > 90 || velocity.abs() > 700;

/// Full-screen photo: no bars or arrows. Tap, or swipe anywhere (up or down), to go back; pinch to zoom, drag to pan
/// while zoomed. Everything moves with the finger and settles in about a tenth of a second.
class ChatPhotoViewer extends StatefulWidget {
  const ChatPhotoViewer({super.key, required this.bytes, this.once = false});
  final Uint8List bytes;
  final bool once;

  @override
  State<ChatPhotoViewer> createState() => _ChatPhotoViewerState();
}

class _ChatPhotoViewerState extends State<ChatPhotoViewer> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this);
  double _scale = 1;
  Offset _off = Offset.zero;
  double _dy = 0;
  double _s0 = 1;
  Offset _o0 = Offset.zero;
  Offset _f0 = Offset.zero;
  bool _zooming = false;
  bool _closing = false;
  Size _size = Size.zero;

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  double get _bg => (1 - _dy.abs() / 320).clamp(0.0, 1.0);

  Offset _clamp(Offset o, double scale) {
    final mx = (_size.width * (scale - 1) / 2).clamp(0.0, 4000.0);
    final my = (_size.height * (scale - 1) / 2).clamp(0.0, 4000.0);
    return Offset(o.dx.clamp(-mx, mx), o.dy.clamp(-my, my));
  }

  void _animateTo({double scale = 1, Offset off = Offset.zero, double dy = 0, int ms = 120, VoidCallback? done}) {
    final (s1, o1, d1) = (_scale, _off, _dy);
    _a.stop();
    _a.duration = Duration(milliseconds: ms);
    void tick() {
      final t = Curves.easeOutCubic.transform(_a.value);
      setState(() {
        _scale = s1 + (scale - s1) * t;
        _off = Offset.lerp(o1, off, t)!;
        _dy = d1 + (dy - d1) * t;
      });
    }

    _a.removeListener(tick);
    _a.addListener(tick);
    _a.forward(from: 0).whenComplete(() {
      _a.removeListener(tick);
      done?.call();
    });
  }

  void _close(double toward) {
    if (_closing) return;
    _closing = true;
    _animateTo(
      dy: toward * (_size.height * 0.7),
      ms: 130,
      done: () {
        if (mounted) Navigator.pop(context);
      },
    );
  }

  void _start(ScaleStartDetails d) {
    if (_closing) return;
    _a.stop();
    _s0 = _scale;
    _o0 = _off;
    _f0 = d.localFocalPoint;
    _zooming = _scale > 1.01;
  }

  void _update(ScaleUpdateDetails d) {
    if (_closing) return;
    if (d.pointerCount >= 2) _zooming = true;
    final center = Offset(_size.width / 2, _size.height / 2);
    if (_zooming) {
      final ns = (_s0 * d.scale).clamp(1.0, 4.0);
      final raw = d.localFocalPoint - center - (_f0 - center - _o0) * (ns / _s0);
      setState(() {
        _scale = ns;
        _off = _clamp(raw, ns);
      });
    } else {
      setState(() => _dy += d.focalPointDelta.dy);
    }
  }

  void _end(ScaleEndDetails d) {
    if (_closing) return;
    if (_zooming) {
      if (_scale < 1.05) _animateTo(ms: 110);
      return;
    }
    final v = d.velocity.pixelsPerSecond.dy;
    if (shouldDismissPhoto(_dy, v)) {
      _close(_dy == 0 ? (v < 0 ? -1 : 1) : _dy.sign);
    } else {
      _animateTo(ms: 110);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      _size = box.biggest;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_scale <= 1.01) _close(1);
          },
          onScaleStart: _start,
          onScaleUpdate: _update,
          onScaleEnd: _end,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: Colors.black.withValues(alpha: _bg)),
              Transform.translate(
                offset: _off + Offset(0, _dy),
                child: Transform.scale(
                  scale: _scale * (1 - (_dy.abs() / 320).clamp(0.0, 1.0) * 0.16),
                  child: Image.memory(widget.bytes, fit: BoxFit.contain, gaplessPlayback: true),
                ),
              ),
              if (widget.once)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 28,
                  child: Opacity(
                    opacity: _bg,
                    child: const Text(
                      'This photo disappears when you close it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, decoration: TextDecoration.none, fontSize: 14),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({super.key, required this.count, required this.onCancel, required this.onReport});
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onCancel,
            tooltip: 'Cancel',
            icon: Icon(PhosphorIconsRegular.x, color: c.ink2),
          ),
          Expanded(
            child: Text(
              '$count selected',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: onReport,
            icon: const Icon(PhosphorIconsRegular.flag, size: 18),
            label: const Text('Report'),
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip(this.date);
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label = DateUtils.isSameDay(date, now)
        ? 'Today'
        : DateUtils.isSameDay(date, now.subtract(const Duration(days: 1)))
        ? 'Yesterday'
        : DateFormat('d MMM yyyy').format(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, height: 16 / 12, color: context.fc.muted),
      ),
    );
  }
}

/// "End-to-end encrypted. Screenshots are off." — only claimed when the
/// backend really encrypts (never in the demo).
class _PrivacyPill extends StatelessWidget {
  const _PrivacyPill({required this.encrypted});
  final bool encrypted;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(encrypted ? PhosphorIconsFill.lockSimple : PhosphorIconsFill.lockSimpleOpen, size: 13, color: c.ink3),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                encrypted ? 'End-to-end encrypted. Screenshots are off.' : 'Demo chat, not encrypted. Screenshots are off.',
                style: TextStyle(fontSize: 13, height: 18 / 13, color: c.ink3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadIntro extends StatelessWidget {
  const _ThreadIntro({required this.peer, required this.encrypted});
  final PublicProfile peer;
  final bool encrypted;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Avatar(url: peer.primaryPhoto, name: peer.fullName, size: 88),
            const SizedBox(height: 14),
            Text('You and ${peer.firstName} are connected', style: t.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              encrypted
                  ? 'Messages and voice notes are end-to-end encrypted. Only you and ${peer.firstName} can read them.'
                  : 'Say hi. Screenshots are blocked in this chat.',
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Drag a message to the left to reply to it (it springs back; vertical scrolling is not affected).
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.child, required this.onReply, required this.enabled});
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const _trigger = 56.0;
  double _dx = 0;
  bool _fired = false;
  bool _dragging = false;

  void _reset() => setState(() {
    _dx = 0;
    _fired = false;
    _dragging = false;
  });

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final c = context.fc;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => setState(() => _dragging = true),
      onHorizontalDragUpdate: (d) {
        setState(() => _dx = (_dx + d.delta.dx).clamp(-84.0, 0.0));
        if (_dx <= -_trigger && !_fired) {
          _fired = true;
          Fx.instance.tap();
        }
      },
      onHorizontalDragEnd: (_) {
        if (_fired) widget.onReply();
        _reset();
      },
      onHorizontalDragCancel: _reset,
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          Positioned(
            right: 10,
            child: Opacity(
              opacity: (-_dx / _trigger).clamp(0.0, 1.0),
              child: Icon(Icons.reply_rounded, size: 22, color: _fired ? c.accent : c.muted),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(end: _dx),
            duration: _dragging ? Duration.zero : Motion.of(context, const Duration(milliseconds: 180)),
            curve: Curves.easeOutCubic,
            builder: (_, v, child) => Transform.translate(offset: Offset(v, 0), child: child),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// "Replying to ..." above the message box.
class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.name, required this.preview, required this.onClose});
  final String name;
  final String preview;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.hair),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to $name',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.accent),
                ),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: c.ink3),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: 'Cancel reply',
            icon: Icon(PhosphorIconsRegular.x, size: 18, color: c.muted),
          ),
        ],
      ),
    );
  }
}

/// The quoted original inside a reply bubble. Tap to jump to it.
class _Quote extends StatelessWidget {
  const _Quote({required this.reply, required this.name, required this.mine, this.onTap});
  final ReplyRef reply;
  final String name;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final fg = mine ? c.onSent : c.ink;
    final label = reply.preview.isEmpty
        ? (reply.kind == 'photo' ? 'Photo' : (reply.kind == 'voice' ? 'Voice message' : 'Message'))
        : reply.preview;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: (mine ? c.onSent : c.ink).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: mine ? c.onSent.withValues(alpha: 0.8) : c.accent, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: mine ? c.onSent : c.accent),
            ),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, height: 1.3, color: fg.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A "view once" photo: the receiver can open it a single time; the sender sees whether it was opened.
class _OnceTile extends ConsumerStatefulWidget {
  const _OnceTile({required this.message, required this.mine, required this.peerId, required this.color, this.openable = true});
  final ChatMessage message;
  final bool mine;
  final String peerId;
  final Color color;
  final bool openable;

  @override
  ConsumerState<_OnceTile> createState() => _OnceTileState();
}

class _OnceTileState extends ConsumerState<_OnceTile> {
  bool _opening = false;

  Future<void> _open() async {
    final m = widget.message;
    if (_opening || widget.mine || m.viewed || (m.image == null && m.localImageUrl == null)) return;
    setState(() => _opening = true);
    try {
      final backend = ref.read(backendProvider);
      final bytes = await backend.imageBytes(m);
      if (!mounted) return;
      await Navigator.push(context, chatPhotoRoute(bytes, once: true));
      // Closed: the photo is gone from this phone.
      await backend.markPhotoViewed(widget.peerId, m.id);
    } catch (_) {
      if (mounted) showSnack(context, 'Couldn’t open the photo. Try again.', icon: PhosphorIconsFill.warningCircle);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final color = widget.color;
    final String title;
    final String sub;
    final bool opened;
    if (m.viewed) {
      title = 'Photo';
      sub = 'Opened';
      opened = true;
    } else if (widget.mine) {
      title = 'Photo · View once';
      sub = m.listenedAt != null ? 'Opened' : 'Not opened yet';
      opened = m.listenedAt != null;
    } else {
      title = 'Photo · View once';
      sub = _opening ? 'Opening…' : 'Tap to view';
      opened = false;
    }
    return Semantics(
      button: !widget.mine && !m.viewed,
      label: '$title, $sub',
      child: GestureDetector(
        onTap: widget.openable ? _open : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The minimal view-once icon: dotted while waiting, solid once it has been opened.
              ViewOnceIcon(size: 26, color: color, filled: opened),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: color),
                  ),
                  Text(sub, style: TextStyle(fontSize: 13, color: color.withValues(alpha: 0.75))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
