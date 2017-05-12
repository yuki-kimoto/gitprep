function insertAtCaret(target, str) {
  var obj = $(target);
  obj.focus();
  if(navigator.userAgent.match(/MSIE/)) {
    var r = document.selection.createRange();
    r.text = str;
    r.select();
  } else {
    var s = obj.val();
    var p = obj.get(0).selectionStart;
    var np = p + str.length;
    obj.val(s.substr(0, p) + str + s.substr(p));
    obj.get(0).setSelectionRange(np, np);
  }
}

function init_icon_input () {
  // Comment icon
  $('.icon-add-header-text').on('click', function () {
    var textarea = $(this).closest('form').find('textarea');
    insertAtCaret(textarea, "# ");
  });
  $('.icon-add-bold-text').on('click', function () {
    var textarea = $(this).closest('form').find('textarea');
    insertAtCaret(textarea, "****");
  });
  $('.icon-add-italic-text').on('click', function () {
    var textarea = $(this).closest('form').find('textarea');
    insertAtCaret(textarea, "__");
  });
  $('.icon-insert-quote').on('click', function () {
    var textarea = $(this).closest('form').find('textarea');
    insertAtCaret(textarea, "> ");
  });
  $('.icon-insert-code').on('click', function () {
    var textarea = $(this).closest('form').find('textarea');
    insertAtCaret(textarea, "``");
  });
  $('.icon-add-link').on('click', function () {
    var textarea = $(this).closest('form').find('textarea');
    insertAtCaret(textarea, "[](url)");
  });
  $('.icon-add-bulleted-list').on('click', function () {
    var textarea = $(this).closest('form').find('textarea');
    insertAtCaret(textarea, "- ");
  });
  $('.icon-add-numbered-list').on('click', function () {
    var textarea = $(this).closest('form').find('textarea');
    insertAtCaret(textarea, "1. ");
  });
  $('.icon-mension-user').on('click', function () {
    var textarea = $(this).closest('form').find('textarea');
    insertAtCaret(textarea, "@");
  });
}
