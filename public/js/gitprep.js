// Gitprep namesspace.
(function(Gitprep, $, undefined) {
  var dateFmt = new Intl.DateTimeFormat(undefined, {    // Tooltips date format.
    dateStyle: 'medium',
    timeStyle: 'long',
  });
  var dayFmt = new Intl.DateTimeFormat(undefined, {    // Commits day format.
    dateStyle: 'medium',
  });

  // Set element tooltip from a Unix timestamp using browser locale and
  // timezone.
  Gitprep.dateTooltip = function (elem, ts) {
    elem.setAttribute('title', dateFmt.format(new Date(ts * 1000)));
    elem.removeAttribute('onmouseover');
  };

  // Split unnumbered list of commits into several lists, one for each day
  // with a day header prepended, taking the browser timezone into account.
  // Each list item holds its Unix timestamp in a "ts" attribute.
  Gitprep.commitsByDay = function (block) {
    $(block).each(function () {
      var container = $(this);
      var dateHeader = $('.commit-date', container).get(0);
      var lastDay;
      var dayUl;

      $('ul > li[ts]', container).each(function () {
        var day = dayFmt.format(new Date($(this).attr('ts') * 1000));
        if (day != lastDay) {
          var dayHeader = $(dateHeader.cloneNode(true));
          var dayLabel = $('.date-text', dayHeader);
          dayLabel.text('Commits on ' + day);
          dayUl = $($(this).parent().get(0).cloneNode(false));
          container.before(dayHeader);
          container.before(dayUl);
          lastDay = day;
        }
        dayUl.append($(this));
      });
      container.remove();
    });
  };

  // Given a css color (possibly in rgb()/hsl() form), return it as '#xxxxxx'.
  Gitprep.standardizeColor = function (str) {
    var ctx = document.createElement('canvas').getContext('2d');
    ctx.fillStyle = str;
    return ctx.fillStyle;
  };

  // Latched mouse coordinates.
  Gitprep.mouseX = 0;
  Gitprep.mouseY = 0;
  $(document).mousemove(function (event) {
    Gitprep.mouseX = event.pageX;
    Gitprep.mouseY = event.pageY;
  });

  // Show a popup during ms milliseconds.
  Gitprep.flashingPopup = function (html, ms, style) {
    var css = {
      position: 'absolute',
      left: Gitprep.mouseX + 8,
      top: Gitprep.mouseY + 8,
      border: '1px solid black',
      background: '#FFFBD6',
      padding: '0.3cap 0.5em',
      ... (style || {})
    };
    ms = ms || 2000;
    var popup = $('<div>');
    popup.css(css);
    popup.html(html);
    setTimeout(function () {
      popup.remove();
    }, ms);
    $('body').append(popup);
  };

  // Initialize comment edition iconic buttons.
  $(document).ready(function () {
    var iconInputButton = function (iconClass, frame, multi, embed) {
      if (!(frame instanceof Array)) {
        frame = [frame, ''];
      }
      if (multi === undefined) {
        multi = frame;
      }
      if (!(multi instanceof Array)) {
        multi = [multi, ''];
      }
      if (embed === undefined) {
        embed = "\n";
      }
      var icon = $(iconClass);
      icon.on('click', function () {
        var textarea = $(this).closest('form').find('textarea');
        var obj = $(textarea);
        obj.focus();
        var text = obj.val();
        var jsobj = $(obj).get(0);
        var start = jsobj.selectionStart;
        var end = jsobj.selectionEnd;
        var lines = text.substring(start, end).split("\n");

        if (lines.length > 1) {
          frame = multi;
        }
        var replacement = lines.join(embed);

        obj.val(text.substring(0, start) +
                frame[0] + replacement + frame[1] +
                text.substring(end));
        start += frame[0].length;
        end = start + replacement.length;
        jsobj.setSelectionRange(start, end);
      });
    };

    iconInputButton('.icon-add-header-text' , '# ');
    iconInputButton('.icon-add-bold-text', ['**', '**']);
    iconInputButton('.icon-add-italic-text', ['_', '_']);
    iconInputButton('.icon-insert-quote', '> ');
    iconInputButton('.icon-insert-code', ['`', '`'], ["```\n", "\n```"]);
    iconInputButton('.icon-add-link', ['[', '](url)']);
    iconInputButton('.icon-add-bulleted-list', '- ', undefined, "\n- ");
    iconInputButton('.icon-add-numbered-list', '1. ', undefined, "\n1. ");
    iconInputButton('.icon-mention-user', '@');
  });
}(window.Gitprep = window.Gitprep || {}, jQuery));
