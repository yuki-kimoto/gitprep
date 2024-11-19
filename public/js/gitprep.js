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

  // Class change event implementation.
  Gitprep.onClassChange = function (selector, callback) {
    $(selector).each(function () {
      new MutationObserver(function (mutations) {
        callback && mutations.forEach(function (mutation) {
          callback(mutation.target, mutation.target.className);
        });
      }).observe(this, {
        attributes: true,
        attributeFilter: ['class']
      });
    });
  };

  // Diff folding.
  var header_text = function (from_line, from_count, to_line, to_count, text) {
    if (from_line == 1 && from_count == 0) {
      from_line = 0;
    }
    if (to_line == 1 && to_count == 0) {
      to_line = 0;
    }
    var t = '@@ -' + from_line.toString();
    if (from_count != 1) {
      t += ',' + from_count.toString();
    }
    t += ' +' + to_line.toString();
    if (to_count != 1) {
      t += ',' + to_count.toString();
    }
    t += ' @@';
    if (text != '') {
      t += ' ' + text;
    }
    return t;
  };
  var parse_diff_chunk_header = function (header) {
    var re = /^@@\s-(\d+)(?:,(\d+))?\s\+(\d+)(?:,(\d+))?\s@@(?:\s(.*?))?\s*$/;
    var m = header.match(re);
    if (m) {
      if (!m[1]) {
        m[1] = '1';
      }
      if (!m[3]) {
        m[3] = '1';
      }
      m = [Number(m[1]), Number(m[2]), Number(m[3]), Number(m[4]), m[5]];
    }
    return m;
  };
  var diff_nodiff_lines = function (lines) {
    var new_lines = [];
    lines.forEach(function (line) {
      var pre = $('<pre>').text(line.text);
      var text = $('<td class="diff-text">').html(pre);
      var from = $('<td class="diff-line">').text(line.from);
      var to = $('<td class="diff-line">').text(line.to);
      var tr = $('<tr class="diff-nodiff">').append(from, to, text);
      new_lines.push(tr);
    });
    return new_lines;
  };
  var diffFold = function (self, direction) {
    var header = $(self).closest('tr');
    var header_text = $('.diff-text', header).text().trim();
    var table = header.closest('table');
    var url = table.attr('foldurl');
    var request = {'op': 'fold-' + direction, 'header': header_text};
    var headers = $('.diff-chunk-header', table);
    var idx = headers.index(header);
    var preheader;
    if (idx > 0) {
      preheader = $(headers.get(idx - 1));
      request.previous_header = $('.diff-text', preheader).text().trim();
    }
    $.ajax({
      type: 'POST',
      url: url,
      dataType: 'json',
      contentType: 'application/json',
      data: JSON.stringify(request),
      success: function(json) {
        if (json.status == 'ok') {
          var lines = diff_nodiff_lines(json.lines || []);
          direction == 'down'? header.before(lines): header.after(lines);
          if (preheader && json.previous_header_text != undefined) {
            $('.diff-text pre', preheader).text(json.previous_header_text);
          }
          if (json.header_text != undefined) {
            $('.diff-text pre', header).text(json.header_text);
          }
          if (json.header_icon != undefined) {
            $('.diff-line', header).replaceWith(json.header_icon);
          } else {
            header.remove();
          }
        }
      }
    });
  };
  Gitprep.diffFoldUp = function (self) {
    diffFold(self, 'up');
  };
  Gitprep.diffFoldDown = function (self) {
    diffFold(self, 'down');
  };
  Gitprep.diffExpand = function (self) {
    var commit_diff = $(self).closest('.commit-diff');
    var table = $('.commit-diff-body table', commit_diff);
    var url = table.attr('foldurl');
    var headers = $('.diff-chunk-header', table);
    var request = {'op': 'expand', 'headers': []};
    headers.each(function (index, header) {
      request.headers.push($('.diff-text', header).text().trim());
    });
    $.ajax({
      type: 'POST',
      url: url,
      dataType: 'json',
      contentType: 'application/json',
      data: JSON.stringify(request),
      success: function(json) {
        if (json.status == 'ok') {
          var parts = json.parts || [];
          var last = parts.pop();
          parts.forEach(function (lines, index) {
            var header = $(headers.get(index));
            var new_lines = diff_nodiff_lines(lines);
            header.after(new_lines);
          });
          var header_1st = headers.first();
          header_1st.parent().append(diff_nodiff_lines(last));
          headers.slice(1).remove();

          $('.diff-text pre', header_1st).text(json.header_text);
          $('.diff-line', header_1st).replaceWith(json.header_icon);
          $('.diff-expand-collapse-button', commit_diff).show();
          $(self).hide();
        }
      }
    });
  };
  Gitprep.diffCollapse = function (self) {
    var commit_diff = $(self).closest('.commit-diff');
    var table = $('.commit-diff-body table', commit_diff);
    var url = table.attr('foldurl');
    var request = {'op': 'collapse'};
    var fl = 1, tl = 1;
    var chunkfl, chunktl;
    var hmodel;
    var chunkfirst;
    var chunks = [];
    var pos = [];

    var start_chunk = function (tr) {
      if (!chunkfirst) {
        chunkfirst = tr;
        chunkfl = fl; chunktl = tl;
      }
    };
    var end_chunk = function () {
      if (chunkfirst) {
        var hdr = header_text(chunkfl, fl - chunkfl, chunktl, tl - chunktl, '');
        pos.push(chunkfirst);
        chunks.push(hdr);
        chunkfirst = undefined;
      }
    };

    $('tr', table).each(function (index, elem) {
      var tr = $(elem);
      if (tr.hasClass('diff-from-file')) {
        start_chunk(tr);
        fl++;
      } else if (tr.hasClass('diff-to-file')) {
        start_chunk(tr);
        tl++;
      } else if (tr.hasClass('diff-neutral')) {
        start_chunk(tr);
        fl++; tl++;
      } else if (tr.hasClass('diff-chunk-header')) {
        end_chunk();
        var h = parse_diff_chunk_header($('.diff-text', tr).text().trim());
        if (h) {
          fl = h[0]; tl = h[2];
        }
        hmodel = tr;
      } else if (tr.hasClass('diff-nodiff')) {
        end_chunk();
        fl++; tl++;
      }
    });
    end_chunk();
    if (hmodel) {
      request.chunks = chunks;
      $.ajax({
        type: 'POST',
        url: url,
        dataType: 'json',
        contentType: 'application/json',
        data: JSON.stringify(request),
        success: function(json) {
          if (json.status == 'ok') {
            var icons = json.icons || [];
            var rm = $('.diff-nodiff', table).add('.diff-chunk-header', table);
            var last = icons.pop();
            var tr;
            icons.forEach(function (icon) {
              chunkfirst = pos.shift();
              var hdr = chunks.shift();
              tr = hmodel.clone();
              $('.diff-line', tr).replaceWith(icon);
              $('.diff-text pre', tr).text(hdr);
              chunkfirst.before(tr);
            });
            tr = hmodel.clone();
            $('.diff-line', tr).replaceWith(last);
            $('.diff-text pre', tr).text('');
            hmodel.parent().append(tr);
            rm.remove();
            $('.diff-expand-collapse-button', commit_diff).show();
            $(self).hide();
          }
        }
      });
    }
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
