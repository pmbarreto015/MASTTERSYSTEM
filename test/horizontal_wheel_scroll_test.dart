import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masttersystem/widgets/horizontal_wheel_scroll.dart';

void main() {
  testWidgets('roda do mouse percorre a barra horizontal nos dois sentidos',
      (tester) async {
    late ScrollController controller;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            height: 50,
            child: HorizontalWheelScroll(builder: (context, scrollController) {
              controller = scrollController;
              return ListView(
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                children: List.generate(
                    10, (index) => SizedBox(width: 100, child: Text('$index'))),
              );
            }),
          ),
        ),
      ),
    ));
    final position = tester.getCenter(find.byType(HorizontalWheelScroll));
    await tester.sendEventToBinding(PointerScrollEvent(
        position: position, scrollDelta: const Offset(0, 120)));
    await tester.pump();
    expect(controller.offset, 120);
    await tester.sendEventToBinding(PointerScrollEvent(
        position: position, scrollDelta: const Offset(0, -120)));
    await tester.pump();
    expect(controller.offset, 0);
  });
}
