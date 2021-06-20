const int OP_RENDER = 0;
const int OP_SET_FRAGMENT = 1;
const int OP_SET_FRAGMENT_ROOT_TEMPLATE = 2;
const int OP_PATCH_FRAGMENT = 3;
const int OP_SET_TEMPLATE = 4;
const int OP_RESET = 5;

class JSONEncoding {
  Map<int, dynamic> fragments = Map();
  Map<int, dynamic> templates = Map();

  dynamic out;

  bool handleMessage(dynamic dynOps) {
    var ops = dynOps as List<dynamic>;
    var rendered = false;

    for (var dynOp in ops) {
      var op = dynOp as List<dynamic>;
      var type = op[0] as int;

      switch(type) {
        case OP_RENDER:
          out = renderFragment(op[1] as int);
          rendered = true;
          break;

        case OP_SET_FRAGMENT:
          this.fragments[op[1] as int] = op[2];
          break;

        case OP_SET_FRAGMENT_ROOT_TEMPLATE:
          this.fragments[op[1] as int] = ["\$t", op[2], ...op.sublist(3)];
          break;

        case OP_PATCH_FRAGMENT:
          throw "unimpl";
          break;

        case OP_SET_TEMPLATE:
          this.templates[op[1] as int] = op[2];
      }
    }

    return rendered;
  }

  dynamic renderFragment(int fragmentId) {
    var body = fragments[fragmentId];
    return this.renderBody(body, null);
  }

  dynamic renderTemplate(int templateId, List<dynamic> slots) {
    var body = templates[templateId];
    return this.renderBody(body, slots);
  }

  dynamic renderBody(dynamic body, List<dynamic>? templateSlots) {
    if (body == null) {
      return null;
    }
    if (body is String || body is num || body is bool) {
      return body;
    }
    if (body is List) {
      var bodyList = body as List<dynamic>;
      if (body[0] == "\$r") {
        return renderFragment(bodyList[1] as int);
      }
      if (body[0] == "\$t") {
        var innerSlots = bodyList.sublist(2)
          .map((slot) => renderBody(slot, templateSlots))
          .toList();
        return renderTemplate(body[1], innerSlots);
      }
      if (body[0] == "\$s") {
        return templateSlots![body[1] as int];
      }
      if (body[0] == "\$e") {
        return body[1];
      }
      return body.map((item) => renderBody(item, templateSlots));
    }
    if (body is Map) {
      var bodyMap = body as Map<String, dynamic>;
      var out = Map();
      for (MapEntry<String, dynamic> item in bodyMap.entries) {
        out[item.key] = renderBody(item.value, templateSlots);
      }
      return out;
    }
    throw "unimpl";
  }

}
