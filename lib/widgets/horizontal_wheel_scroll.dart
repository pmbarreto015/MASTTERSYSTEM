import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Permite que a roda vertical do mouse percorra uma lista horizontal.
class HorizontalWheelScroll extends StatefulWidget {
  const HorizontalWheelScroll({super.key, required this.builder});

  final Widget Function(BuildContext context, ScrollController controller)
      builder;

  @override
  State<HorizontalWheelScroll> createState() => _HorizontalWheelScrollState();
}

class _HorizontalWheelScrollState extends State<HorizontalWheelScroll> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy == 0 ||
        event.scrollDelta.dx != 0 ||
        !_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    final target = (position.pixels + event.scrollDelta.dy)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (target == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (_controller.hasClients) _controller.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerSignal: _onPointerSignal,
        child: widget.builder(context, _controller),
      );
}
