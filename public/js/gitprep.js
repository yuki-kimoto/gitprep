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
  Gitprep.commitsByDay = function (ul) {
    var container = $(ul);
    var lastDay;
    var dayUl;

    $('li[ts]', container).each(function () {
      var day = dayFmt.format(new Date($(this).attr('ts') * 1000));
      if (day != lastDay) {
        var dayHeader = $('<div class="commit-date"><i class="icon-off"></i></div>');
        var dayLabel = $('<span></span>');
        dayLabel.text('Commits on ' + day);
        dayHeader.append(dayLabel);
        container.before(dayHeader);
        dayUl = $(container.get(0).cloneNode(false));
        container.before(dayUl);
        lastDay = day;
      }
      dayUl.append($(this));
    });
    container.remove();
  };
}(window.Gitprep = window.Gitprep || {}, jQuery));
