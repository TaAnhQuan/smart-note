import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:saber/components/toolbar/content_extract_painter.dart';

class ContentExtractWidget extends StatefulWidget {
  final Widget child;
  final Function(Uint8List imageData, Rect searchArea)? onSearch;
  final Function()? onToggleSplit;
  final bool isGestureSearchEnabled;

  const ContentExtractWidget({
    super.key,
    required this.child,
    this.onSearch,
    this.onToggleSplit,
    required this.isGestureSearchEnabled,
  });

  @override
  _ContentExtractWidgetState createState() => _ContentExtractWidgetState();
}

class _ContentExtractWidgetState extends State<ContentExtractWidget> with TickerProviderStateMixin {
  late AnimationController _selectionAnimationController;
  late AnimationController _pulseAnimationController;
  late Animation<double> _selectionAnimation;
  late Animation<double> _pulseAnimation;

  final List<Offset> _gesturePoints = [];
  bool _isDrawing = false;
  bool _isSearching = false;
  bool _selectionActive = false;
  Rect? _selectionRect;
  Uint8List? _selectedImageData;

  final GlobalKey _captureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selectionAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _pulseAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _selectionAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _selectionAnimationController, curve: Curves.easeOutCubic),
    );
    _pulseAnimation = Tween<double>(begin: 1, end: 1.2).animate(
      CurvedAnimation(parent: _pulseAnimationController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _selectionAnimationController.dispose();
    _pulseAnimationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ContentExtractWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isGestureSearchEnabled && !widget.isGestureSearchEnabled && !_selectionActive) {
      _resetSearchState(fullReset: true);
    }
  }

  bool _processGestureForBoundingBox(List<Offset> points) {
    if (points.length < 20) return false;

    final startPoint = points.first;
    final endPoint = points.last;
    final distance = (endPoint - startPoint).distance;
    if (distance > 60.0) return false;

    double minX = points.first.dx;
    double maxX = points.first.dx;
    double minY = points.first.dy;
    double maxY = points.first.dy;

    for (Offset point in points) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
      minY = math.min(minY, point.dy);
      maxY = math.max(maxY, point.dy);
    }

    final rect = Rect.fromLTRB(minX, minY, maxX, maxY);
    if (rect.width < 50 || rect.height < 50) return false;

    _selectionRect = rect;
    return true;
  }

  void _onPanStart(DragStartDetails details) {
    if (_selectionActive) return;
    _resetSearchState(fullReset: false);
    setState(() {
      _gesturePoints.add(details.localPosition);
      _isDrawing = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isDrawing) {
      setState(() {
        _gesturePoints.add(details.localPosition);
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isDrawing && _processGestureForBoundingBox(_gesturePoints)) {
      setState(() {
        _isDrawing = false;
      });
      _performSearch();
    } else {
      _resetSearchState(fullReset: false);
    }
  }

  void _performSearch() async {
    if (_selectionRect == null) return;

    setState(() {
      _isSearching = true;
    });

    _selectionAnimationController.forward();
    await Future.delayed(const Duration(milliseconds: 100));
    _pulseAnimationController.forward();

    try {
      final imageData = await _captureWidgetAsImage();
      if (imageData != null) {
        setState(() {
          _selectedImageData = imageData;
          _selectionActive = true;
        });
        if (widget.onSearch != null) {
          widget.onSearch!(imageData, _selectionRect!);
        }
        _showSearchResults();
      } else {
        _resetSearchState(fullReset: true);
      }
    } catch (e) {
      print('Error capturing image: $e');
      _showErrorMessage();
      _resetSearchState(fullReset: true);
    }

    setState(() {
      _isSearching = false;
    });
  }

  Future<Uint8List?> _captureWidgetAsImage() async {
    try {
      RenderRepaintBoundary boundary =
      _captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 2);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      print('Failed to capture image: $e');
      return null;
    }
  }

  void _showSearchResults() {
    if (_selectionRect == null || _selectedImageData == null) return;

    widget.onToggleSplit?.call();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Search results opened in Chat Screen'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showErrorMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Unable to capture search area. Please try again.'),
        backgroundColor: Colors.red[400],
      ),
    );
  }

  void _resetSearchState({required bool fullReset}) {
    setState(() {
      _gesturePoints.clear();
      _isDrawing = false;
      _isSearching = false;
      if (fullReset) {
        _selectionRect = null;
        _selectedImageData = null;
        _selectionActive = false;
      }
    });
    _selectionAnimationController.reset();
    _pulseAnimationController.reset();
  }

  void _clearSelection() {
    _resetSearchState(fullReset: true);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _captureKey,
      child: GestureDetector(
        onPanStart: widget.isGestureSearchEnabled ? _onPanStart : null,
        onPanUpdate: widget.isGestureSearchEnabled ? _onPanUpdate : null,
        onPanEnd: widget.isGestureSearchEnabled ? _onPanEnd : null,
        onTap: () {
          if (_selectionActive && !_isSearching && !_isDrawing) {
            _clearSelection();
          }
        },
        child: Stack(
          children: [
            widget.child,
            if (_isDrawing || _selectionActive)
              AnimatedBuilder(
                animation: Listenable.merge([_selectionAnimation, _pulseAnimation]),
                builder: (context, child) {
                  return CustomPaint(
                    painter: ContentExtractSelectionPainter(
                      gesturePoints: _gesturePoints,
                      selectionRect: _selectionRect,
                      animationValue: _selectionAnimation.value,
                      pulseValue: _pulseAnimation.value,
                      isDrawing: _isDrawing,
                    ),
                    size: Size.infinite,
                  );
                },
              ),
            if (_isSearching && _selectionRect != null)
              Positioned(
                left: _selectionRect!.center.dx - 20,
                top: _selectionRect!.center.dy - 20,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
