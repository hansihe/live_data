import 'dart:developer';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:live_data_client/live_data_client.dart';
import './live_data.dart';
import './widget_registry.dart';

typedef Widget MakeFallbackFn();

Widget emptyFallback() {
  return Container();
}

class LiveNativeMount extends StatefulWidget {
  final WidgetRegistry registry;
  final String route;

  final MakeFallbackFn makeFallback;

  LiveNativeMount(this.registry, this.route,
      {this.makeFallback = emptyFallback});

  @override
  _LiveNativeMountState createState() {
    return _LiveNativeMountState();
  }
}

class _LiveNativeMountState extends State<LiveNativeMount> {
  bool inited = false;

  late LiveDataSocket socket;
  late LiveData data;

  late WidgetRegistry registry;

  dynamic tree;

  @override
  void didUpdateWidget(LiveNativeMount oldWidget) {
    if (oldWidget.route != widget.route)
      throw "route cannot be changed on mounted LiveNative";

    super.didUpdateWidget(oldWidget);

    setState(() {
      registry = widget.registry;
    });
  }

  @override
  void didChangeDependencies() {
    var newSocketService = DataViewSocketService.of(context);
    if (!inited) {
      inited = true;

      registry = widget.registry;

      socket = newSocketService.socket;

      data = socket.liveData(widget.route, {});

      data.dataStream.listen((data) {
        setState(() {
          tree = data;
        });
      });
    } else if (socket != newSocketService.socket) {
      throw "LiveNative mount changed socket";
    }

    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    if (tree == null) return widget.makeFallback();

    log("$tree");

    var context = RegistryBuildContext(widget.registry, data);
    return context.build(tree);
  }
}
