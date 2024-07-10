function init_icon_input () {
  var get;
  var put;
  var preset;

  if(navigator.userAgent.match(/MSIE/)) {
    preset = function(obj) {
      var r = document.selection.createRange();
      obj.data('iconInputData', {
        'from': 0,
        'to': r.text.length,
        'infix': r.text,
        'range': r
      });
    }
    get = function(obj) {
      return obj.data('iconInputData');
    }
    put = function(target) {
      target['range'].text = target['infix'];
      target['range'].select();
    }
  }
  else {
    get = function(obj) {
      var s = obj.val();
      var p = obj.get(0).selectionStart;
      var e = obj.get(0).selectionEnd;
      return {
        'from': p,
        'to': e,
        'prefix': s.substring(0, p),
        'infix': s.substring(p, e),
        'suffix': s.substring(e),
        'obj': obj
      };
    }
    put = function(target) {
      var obj = target['obj'];
      obj.val(target['prefix'] + target['infix'] + target['suffix']);
      obj.get(0).setSelectionRange(target['from'], target['to']);
    }
  }

  var iconResponse = function(icon, single, multi, embed) {
    var textarea = $(icon).closest('form').find('textarea');
    var obj = $(textarea);
    obj.focus();
    var target = get(obj);
    var sellen = target['infix'].length;
    var lines = target['infix'].split("\n");
    if (multi !== undefined && lines.length > 1) {
      single = multi;
    }
    if (embed === undefined) {
      embed = "\n";
    }
    var before = single[0];
    var after = single[1];
    if (after === undefined) {
      after = "";
    }
    target['infix'] = before + lines.join(embed) + after;
    target['to'] += target['infix'].length - sellen - after.length;
    target['from'] += before.length;
    put(target);
  }

  var setEvents = function(iconclass, callback) {
    var icon = $(iconclass);
    if (preset) {
      icon.on('mousedown', function () {
        var textarea = $(this).closest('form').find('textarea');
        var obj = $(textarea);
        obj.focus();
        preset(obj);
      });
    }
    icon.on('click', callback);
  }

  // Comment icon
  setEvents('.icon-add-header-text', function () {
    iconResponse(this, ["# "]);
  });
  setEvents('.icon-add-bold-text', function () {
    iconResponse(this, ["**", "**"]);
  });
  setEvents('.icon-add-italic-text', function () {
    iconResponse(this, ["_", "_"]);
  });
  setEvents('.icon-insert-quote', function () {
    iconResponse(this, ["> "]);
  });
  setEvents('.icon-insert-code', function () {
    iconResponse(this, ["`", "`"], ["```\n", "\n```"]);
  });
  setEvents('.icon-add-link', function () {
    iconResponse(this, ["[", "](url)"]);
  });
  setEvents('.icon-add-bulleted-list', function () {
    iconResponse(this, ["- "], undefined, "\n- ");
  });
  setEvents('.icon-add-numbered-list', function () {
    iconResponse(this, ["1. "], undefined, "\n1. ");
  });
  setEvents('.icon-mention-user', function () {
    iconResponse(this, ["@"]);
  });
}
