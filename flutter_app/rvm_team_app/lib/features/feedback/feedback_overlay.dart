import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app_feedback.dart';
import '../../bloc/team_auth_bloc.dart';
import '../../data/repositories/ess_repository.dart';
import '../../domain/ess_models.dart';
import '../../injection.dart';
import '../../widgets/team_kit.dart';
import 'feedback_visibility.dart';

/// The one floating Feedback control (#153), docked to the left edge at
/// mid-height and draggable vertically. It is not a FAB, so it stays clear of
/// the shell's bottom bar, the stacked Wall FABs, composers and save bars.
class FeedbackOverlay extends StatefulWidget {
  const FeedbackOverlay({
    super.key,
    required this.router,
    required this.child,
  });

  final GoRouter router;
  final Widget child;

  @override
  State<FeedbackOverlay> createState() => _FeedbackOverlayState();
}

class _FeedbackOverlayState extends State<FeedbackOverlay> {
  static double? _savedTop;
  double? _top;

  static const _hiddenRoutes = {
    '/splash',
    '/login',
    '/forgot',
    '/feedback',
  };

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<TeamAuthBloc>().state;
    final caps = context.watch<CapabilitiesBloc>().state.data;
    final path = widget.router.routerDelegate.currentConfiguration.uri.path;
    final visible = auth.status == TeamAuthStatus.authenticated &&
        caps?.feedbackSend == true &&
        !_hiddenRoutes.contains(path) &&
        !feedbackModalOpen.value &&
        !feedbackShellBlocked.value &&
        !feedbackVersionBlocked.value;
    if (!visible) return widget.child;

    final size = MediaQuery.sizeOf(context);
    _top ??= _savedTop ?? (size.height * 0.42);
    final top = (_top ?? 0).clamp(80.0, size.height - 150);

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          top: top,
          child: _FeedbackTab(
            onTap: () => _open(context),
            onDrag: (delta) {
              setState(() {
                _top = (top + delta).clamp(80.0, size.height - 150);
                _savedTop = _top;
              });
            },
          ),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FeedbackSheet(router: widget.router),
    );
  }
}

class _FeedbackTab extends StatelessWidget {
  const _FeedbackTab({required this.onTap, required this.onDrag});

  final VoidCallback onTap;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: 'Send feedback',
      child: GestureDetector(
        onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
        child: Material(
          color: p.primary,
          elevation: 3,
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(RvmRadii.sm + 2),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(RvmRadii.sm + 2),
            ),
            child: SizedBox(
              width: 34,
              height: 68,
              child: Icon(
                Icons.feedback_outlined,
                size: 19,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The feedback sheet: kind, message and one optional screenshot.
class FeedbackSheet extends StatefulWidget {
  const FeedbackSheet({super.key, required this.router});

  final GoRouter router;

  @override
  State<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<FeedbackSheet> {
  final _message = TextEditingController();
  AppFeedbackKind _kind = AppFeedbackKind.bug;
  AppFeedbackContext _context = const AppFeedbackContext();
  Uint8List? _screenshot;
  String _screenshotType = 'image/png';
  bool _busy = false;
  bool _picking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    AppFeedbackContext context = AppFeedbackContext(
      screen: widget.router.routerDelegate.currentConfiguration.uri.toString(),
      platform: Platform.isAndroid ? 'android' : Platform.operatingSystem,
    );
    try {
      final pkg = await PackageInfo.fromPlatform();
      context = AppFeedbackContext(
        screen: context.screen,
        appVersion: pkg.version,
        buildNumber: pkg.buildNumber,
        platform: context.platform,
        osVersion: context.osVersion,
        deviceModel: context.deviceModel,
      );
    } catch (_) {}
    try {
      final device = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await device.androidInfo;
        context = AppFeedbackContext(
          screen: context.screen,
          appVersion: context.appVersion,
          buildNumber: context.buildNumber,
          platform: context.platform,
          osVersion: '${info.version.release} (SDK ${info.version.sdkInt})',
          deviceModel: info.model,
        );
      }
    } catch (_) {}
    if (mounted) setState(() => _context = context);
  }

  Future<void> _pickScreenshot() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      if (bytes == null) return;
      final shrunk = await _shrink(bytes);
      if (!mounted) return;
      if (shrunk == null) {
        setState(
            () => _error = 'That image is too large. Choose a smaller one.');
        return;
      }
      setState(() {
        _screenshot = shrunk;
        _screenshotType = 'image/png';
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'The image could not be read.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Downscales a picked image until its PNG is at most 2 MB.
  Future<Uint8List?> _shrink(Uint8List bytes) async {
    for (final width in [1440, 1280, 1024, 800, 640]) {
      try {
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        frame.image.dispose();
        codec.dispose();
        if (data != null && data.lengthInBytes <= 2 * 1024 * 1024) {
          return data.buffer.asUint8List();
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> _send() async {
    final message = _message.text.trim();
    if (message.length < 5) {
      setState(() => _error = 'Write at least 5 characters.');
      return;
    }
    if (message.length > 2000) {
      setState(() => _error = 'Keep it to 2,000 characters or fewer.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await getIt<EssRepository>().sendFeedback(
        kind: _kind,
        message: message,
        context: _context,
        screenshotBytes: _screenshot,
        contentType: _screenshotType,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppMessage('Thank you. Your feedback was sent.');
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.code == 'MODULE_NOT_INSTALLED'
            ? "Feedback isn't switched on yet."
            : failure.message;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
        left: RvmSpacing.lg,
        right: RvmSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + RvmSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TeamSheetHeader(
              title: 'Send feedback',
              icon: Icons.feedback_outlined,
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: RvmSpacing.md),
            TeamSegmentedTabs(
              labels: const ['Bug', 'Suggestion', 'Other'],
              selectedIndex: _kind.index,
              onChanged: (i) =>
                  setState(() => _kind = AppFeedbackKind.values[i]),
            ),
            const SizedBox(height: RvmSpacing.md),
            TextField(
              controller: _message,
              minLines: 4,
              maxLines: 8,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'What happened?',
                hintText: 'Tell us what went wrong or what would help.',
                alignLabelWithHint: true,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: RvmSpacing.sm),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _picking ? null : _pickScreenshot,
                  icon: Icon(
                    _screenshot == null
                        ? Icons.add_photo_alternate_outlined
                        : Icons.check_circle_outline,
                    size: 18,
                  ),
                  label: Text(
                    _picking
                        ? 'Reading…'
                        : _screenshot == null
                            ? 'Add a screenshot'
                            : 'Screenshot added',
                  ),
                ),
                if (_screenshot != null) ...[
                  const SizedBox(width: RvmSpacing.sm),
                  TextButton(
                    onPressed: () => setState(() => _screenshot = null),
                    child: const Text('Remove'),
                  ),
                ],
              ],
            ),
            if (_context.summary.isNotEmpty) ...[
              const SizedBox(height: RvmSpacing.sm),
              Text(
                _context.summary,
                style: text.bodySmall?.copyWith(color: p.muted),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: RvmSpacing.sm),
              Text(_error!, style: text.bodyMedium?.copyWith(color: p.danger)),
            ],
            const SizedBox(height: RvmSpacing.md),
            TeamPrimaryButton(
              label: 'Send',
              icon: Icons.send_rounded,
              busy: _busy,
              onPressed: _busy ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}
