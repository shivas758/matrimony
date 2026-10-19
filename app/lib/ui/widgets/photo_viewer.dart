import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_client.dart';
import '../strings.dart';
import 'common.dart';

/// A profile photo shown whole (SPEC §9.17): fitted inside its frame over a
/// blurred, enlarged copy of itself, so nothing is cut off whatever the
/// photo's shape. Both layers resolve to the same cached download.
class WholePhoto extends StatelessWidget {
  const WholePhoto({super.key, required this.url, required this.api, this.onTap});

  final String url;
  final ApiClient api;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: AuthedPhoto(url: url, api: api),
            ),
          ),
          // Dims the blurred fill so the real photo stands out from it.
          const ColoredBox(color: Color(0x40000000)),
          Semantics(
            label: S.viewFullPhoto,
            child: AuthedPhoto(url: url, api: api, fit: BoxFit.contain, alignment: Alignment.center),
          ),
        ],
      ),
    );
  }
}

/// Full-screen photo viewer (SPEC §9.17): swipe between a profile's photos,
/// pinch or double-tap to zoom. Opens at the tapped photo.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.urls, required this.api, this.initialIndex = 0});

  final List<String> urls;
  final ApiClient api;
  final int initialIndex;

  static Future<void> open(
    BuildContext context, {
    required List<String> urls,
    required ApiClient api,
    int initialIndex = 0,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PhotoViewer(urls: urls, api: api, initialIndex: initialIndex),
      ),
    );
  }

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pages;
  late int _index;

  /// While a photo is zoomed in, a horizontal drag pans it instead of turning the page.
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.urls.isEmpty ? 0 : widget.urls.length - 1);
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.urls.length;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          tooltip: S.close,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: total > 1 ? Text('${_index + 1}/$total') : null,
      ),
      body: PageView.builder(
        controller: _pages,
        physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
        itemCount: total,
        onPageChanged: (i) => setState(() {
          _index = i;
          _zoomed = false;
        }),
        itemBuilder: (_, i) => _ZoomablePhoto(
          url: widget.urls[i],
          api: widget.api,
          onZoomChanged: (zoomed) {
            if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
          },
        ),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({required this.url, required this.api, required this.onZoomChanged});

  final String url;
  final ApiClient api;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final _transform = TransformationController();
  Offset _doubleTapAt = Offset.zero;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  bool get _isZoomed => _transform.value.getMaxScaleOnAxis() > 1.01;

  void _toggleZoom() {
    if (_isZoomed) {
      _transform.value = Matrix4.identity();
    } else {
      // Zoom 2.5× around the tapped point.
      const scale = 2.5;
      final p = _doubleTapAt;
      _transform.value = Matrix4.identity()
        ..translateByDouble(-p.dx * (scale - 1), -p.dy * (scale - 1), 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
    }
    widget.onZoomChanged(_isZoomed);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 5,
        onInteractionEnd: (_) => widget.onZoomChanged(_isZoomed),
        child: SizedBox.expand(
          child: AuthedPhoto(
            url: widget.url,
            api: widget.api,
            fit: BoxFit.contain,
            alignment: Alignment.center,
          ),
        ),
      ),
    );
  }
}
