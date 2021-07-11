import 'dart:developer';

import '../../../live_data_client.dart';
import '../widget_registry.dart';
import './util.dart';
import 'package:flutter/widgets.dart';

class ListViewFactory extends WidgetFactory {
  static void register(WidgetRegistry registry) {
    registry.register('list_view', ListViewFactory());
  }
  @override
  ListView build(Map<dynamic, dynamic> tree, RegistryBuildContext context) {
    var children = tree['children'].toList();
    var builtChildren = children.map<Widget>((e) => context.build(e)).toList();

    return ListView(
      children: builtChildren,
    );
  }
}

class FlexFactory extends WidgetFactory {
  static void register(WidgetRegistry registry) {
    registry.register('flex', FlexFactory());
  }
  @override
  Flex build(Map<dynamic, dynamic> tree, RegistryBuildContext context) {
    var children = tree['children'];

    var direction;
    switch (tree['direction']) {
      case null:
      case 'column':
        direction = Axis.vertical;
        break;
      case 'row':
        direction = Axis.horizontal;
        break;
      default:
        throw "unknown direction: ${tree["direction"]}";
    }

    return Flex(
      direction: direction,
      key: context.maybeBuildKey(tree['key']),
      children: children.map<Widget>((e) => context.build(e)).toList(),
    );
  }
}

class TextFactory extends WidgetFactory {
  static void register(WidgetRegistry registry) {
    registry.register('text', TextFactory());
  }
  @override
  Text build(Map<dynamic, dynamic> tree, RegistryBuildContext context) {
    return Text(
      tree['text']!,
      style: buildTextStyle(tree['style']),
    );
  }
}

class ContainerFactory extends WidgetFactory {
  static void register(WidgetRegistry registry) {
    registry.register('container', ContainerFactory());
  }
  @override
  Container build(Map<dynamic, dynamic> tree, RegistryBuildContext context) {
    return Container(
      padding: buildEdgeInsertsGeometry(tree['padding']),
      margin: buildEdgeInsertsGeometry(tree['margin']),
      child: context.maybeBuild(tree['child']),
    );
  }
}

class NativeViewForm extends StatefulWidget {
  final Widget child;
  final LiveData data;
  final String? onValidateEvent;

  static NativeFormManager managerOf(BuildContext context) {
    var provider = context.dependOnInheritedWidgetOfExactType<_NativeViewFormProvider>();
    return provider!.formManager;
  }

  NativeViewForm({required this.child, required this.data, required this.onValidateEvent});

  @override
  State<StatefulWidget> createState() => _NativeViewFormState();
}

class _NativeViewFormState extends State<NativeViewForm> implements NativeFormManager {
  Map<String, NativeFormField> fields = {};

  @override
  Widget build(BuildContext context) {
    return _NativeViewFormProvider(
      formManager: this,
      child: widget.child,
    );
  }

  @override
  void registerField(String fieldName, fieldObject) {
    log('register $fieldName');
    assert(!fields.containsKey(fieldName));
    fields[fieldName] = fieldObject;
  }

  @override
  void unregisterField(String fieldName) {
    log('unregister $fieldName');
    fields.remove(fieldName);
  }

  @override
  void handleFieldBlur(String fileName) {
    var values = fields.map((key, value) => MapEntry(key, value.getValue()));

    if (widget.onValidateEvent != null) {
      widget.data.pushEvent({
        'e': widget.onValidateEvent,
        'data': values,
      });
    }
  }
}

abstract class NativeFormManager {
  void registerField(String fieldName, dynamic fieldObject);
  void unregisterField(String fieldName);

  void handleFieldBlur(String fileName);
}

abstract class NativeFormField {
  dynamic getValue();
}

class _NativeViewFormProvider extends InheritedWidget {
  final NativeFormManager formManager;

  _NativeViewFormProvider({Key? key, required this.formManager, required child}): super(key: key, child: child);

  @override
  bool updateShouldNotify(_NativeViewFormProvider oldWidget) => false;
}

class NativeViewFormFactory extends WidgetFactory {
  static void register(WidgetRegistry registry) {
    registry.register('form', NativeViewFormFactory());
  }
  @override
  NativeViewForm build(Map<dynamic, dynamic> tree, RegistryBuildContext context) {
    return NativeViewForm(
      data: context.data,
      onValidateEvent: tree['validate_event'],
      child: context.build(tree['child']),
    );
  }
}

void registerBasicWidgets(WidgetRegistry registry) {
  ListViewFactory.register(registry);
  FlexFactory.register(registry);
  TextFactory.register(registry);
  ContainerFactory.register(registry);
  NativeViewFormFactory.register(registry);
}
