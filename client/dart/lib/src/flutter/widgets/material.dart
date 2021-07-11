import 'dart:developer';

import 'package:flutter/material.dart';
import '../widget_registry.dart';
import 'basic.dart';

class ScaffoldFactory extends WidgetFactory {
  static void register(WidgetRegistry registry) {
    registry.register('scaffold', ScaffoldFactory());
  }
  @override
  Scaffold build(Map<dynamic, dynamic> tree, RegistryBuildContext context) {
    return Scaffold(
      appBar: context.maybeBuild(tree['app_bar']) as PreferredSizeWidget?,
      body: context.maybeBuild(tree['body']),
      floatingActionButton: context.maybeBuild(tree['floating_action_button']),
    );
  }
}

class AppBarFactory extends WidgetFactory {
  static void register(WidgetRegistry registry) {
    registry.register('app_bar', AppBarFactory());
  }
  @override
  AppBar build(Map<dynamic, dynamic> tree, RegistryBuildContext context) {
    return AppBar(
      title: context.maybeBuild(tree['title']),
    );
  }
}

class FloatingActionButtonFactory extends WidgetFactory {
  static void register(WidgetRegistry registry) {
    registry.register('floating_action_button', FloatingActionButtonFactory());
  }
  @override
  FloatingActionButton build(Map<dynamic, dynamic> tree, RegistryBuildContext context) {
    var onPressedEvent = tree['on_pressed_event'] as String?;
    return FloatingActionButton(
      onPressed: () {
        if (onPressedEvent != null) {
          context.pushEvent(onPressedEvent);
        }
      },
    );
  }
}

class FormTextField extends StatefulWidget {
  final String fieldName;
  final InputDecoration decoration;

  FormTextField({
    required this.fieldName,
    required this.decoration,
  });

  @override
  State<StatefulWidget> createState() {
    return _FormTextFieldState();
  }
}

class _FormTextFieldState extends State<FormTextField> implements NativeFormField {
  final TextEditingController controller = TextEditingController();
  final FocusNode focusNode = FocusNode();
  NativeFormManager? manager;

  late bool focused;
  bool active = false;

  @override
  void initState() {
    super.initState();
    focused = focusNode.hasFocus;
    focusNode.addListener(() {
      if (focusNode.hasFocus != focused) {
        focused = focusNode.hasFocus;
        if (!focused) {
          manager!.handleFieldBlur(widget.fieldName);
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    var newManager = NativeViewForm.managerOf(context);
    if (manager != newManager && manager != null) {
      manager!.unregisterField(widget.fieldName);
    }
    manager = newManager;
    manager!.registerField(widget.fieldName, this);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: widget.decoration,
      focusNode: focusNode,
      onChanged: (text) {
        active = true;
      },
    );
  }

  @override
  dynamic getValue() => controller.value.text;

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }
}

class FormTextFieldFactory extends WidgetFactory {
  static void register(WidgetRegistry registry) {
    registry.register('form_text_input', FormTextFieldFactory());
  }
  @override
  FormTextField build(Map<dynamic, dynamic> tree, RegistryBuildContext context) {
    return FormTextField(
      fieldName: tree['field'],
      decoration: InputDecoration(),
    );
  }
}

void registerMaterialWidgets(WidgetRegistry registry) {
  ScaffoldFactory.register(registry);
  AppBarFactory.register(registry);
  FloatingActionButtonFactory.register(registry);
  FormTextFieldFactory.register(registry);
}
