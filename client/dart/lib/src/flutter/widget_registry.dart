import 'package:flutter/widgets.dart';
import 'package:live_data_client/live_data_client.dart';

/// The WidgetRegistry allows you to register widgets that can be constructed
/// by a LiveNative.
class WidgetRegistry {
  Map<String, WidgetFactory> widgets = new Map();

  register(String ident, WidgetFactory factory) {
    if (widgets.containsKey(ident)) {
      throw "widget factory already registered for ident $ident}";
    }
    widgets[ident] = factory;
  }

  unregister(String ident) {
    widgets.remove(ident);
  }
}

class RegistryBuildContext {
  final WidgetRegistry registry;
  final LiveData data;

  RegistryBuildContext(this.registry, this.data);

  pushEvent(String event) {
    this.data.pushEvent({"e": event});
  }

  Widget? maybeBuild(dynamic tree) {
    if (tree != null) return build(tree);
  }

  Widget build(Map<dynamic, dynamic> tree) {
    var ident = tree["t"]! as String;
    if (!registry.widgets.containsKey(ident)) {
      throw "ident `$ident` is not in WidgetRegistry (in registry: ${registry.widgets.keys.toString()})";
    }

    var widget = registry.widgets[ident]!;
    return widget.build(tree, this);
  }

  Key? maybeBuildKey(dynamic data) {
    if (data != null) return buildKey(data);
  }

  Key buildKey(dynamic data) {
    throw UnimplementedError();
  }
}

abstract class WidgetFactory {
  Widget build(Map<dynamic, dynamic> tree, RegistryBuildContext context);
}