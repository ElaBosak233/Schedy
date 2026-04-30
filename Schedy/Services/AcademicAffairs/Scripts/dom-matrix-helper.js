function parseTableToGrid(tableNode) {
  if (!tableNode) return [];
  var trs = Array.from(tableNode.querySelectorAll('tr'));
  var grid = [];
  for (var r = 0; r < trs.length; r++) {
    var tds = Array.from(trs[r].querySelectorAll('td, th'));
    var c = 0;
    grid[r] = grid[r] || [];
    for (var i = 0; i < tds.length; i++) {
      var td = tds[i];
      while (grid[r][c] !== undefined) c++;
      var rowspan = parseInt(td.getAttribute('rowspan')) || 1;
      var colspan = parseInt(td.getAttribute('colspan')) || 1;
      for (var rr = 0; rr < rowspan; rr++) {
        for (var cc = 0; cc < colspan; cc++) {
          grid[r + rr] = grid[r + rr] || [];
          grid[r + rr][c + cc] = {
            html: td.innerHTML,
            text: (td.innerText || td.textContent || '').trim(),
            td: td,
            isOrigin: rr === 0 && cc === 0,
            rowspan: rowspan,
            colspan: colspan
          };
        }
      }
      c += colspan;
    }
  }
  return grid;
}

function publishError(message) {
  document.title = 'KEBIAO_ERR:' + message;
}

function publishCourses(courses) {
  document.title = courses.length ? 'KEBIAO_OK:' + courses.join('|') : 'KEBIAO_ERR:未能提取到课程数据';
}

function isBlank(text) {
  var value = String(text || '').replace(/\s+/g, '');
  return !value || value === '&nbsp;';
}

function sanitize(value) {
  return String(value || '').replace(/[~|]/g, ' ').replace(/\s+/g, ' ').trim();
}

function safeJoin(parts) {
  return parts.map(sanitize).join('~');
}

function readNumber(value) {
  var m = String(value || '').match(/\d+/);
  return m ? parseInt(m[0]) : 0;
}

function textChunks(html) {
  var normalized = String(html || '')
    .replace(/<br\s*\/?\s*>/gi, '\n')
    .replace(/<\/p>|<\/div>|<hr\s*\/?\s*>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ');
  return normalized.split(/\n+/).map(sanitize).filter(Boolean);
}

function splitCourseBlocks(html) {
  return String(html || '')
    .split(/-{5,}|={5,}|<hr\s*\/?\s*>/i)
    .filter(function(v) { return sanitize(v).length > 0; });
}

function courseFromChunks(chunks, day, row, rowspan) {
  var name = chunks[0] || '';
  if (!name || name.indexOf('星期') !== -1 || name.indexOf('节次') !== -1) return null;
  var room = '';
  var weeks = '';
  var teacher = '';
  for (var i = 1; i < chunks.length; i++) {
    var item = chunks[i];
    if (!weeks && (item.indexOf('周') !== -1 || /\d+\s*[-,，~～]\s*\d+/.test(item))) weeks = item;
    else if (!teacher && (item.indexOf('教师') !== -1 || item.indexOf('老师') !== -1 || item.length <= 4)) teacher = item;
    else if (!room) room = item;
  }
  if (!room && chunks.length > 2) room = chunks[2] || '';
  if (!weeks && chunks.length > 1) weeks = chunks[1] || '';
  var start = row * 2 - 1;
  var end = start + rowspan * 2 - 1;
  return safeJoin([name, day, start + '-' + end, room, weeks, teacher]);
}

function coursesFromFloatingItems() {
  var nodes = document.querySelectorAll('.course-cell, .timetable-item, .kbcontent, .course-content, .course-item, .kc-item, .schedule-item');
  var courses = [];
  for (var i = 0; i < nodes.length; i++) {
    var chunks = textChunks(nodes[i].innerHTML);
    if (chunks.length === 0) continue;
    var style = window.getComputedStyle(nodes[i]);
    var day = readNumber(nodes[i].getAttribute('data-day')) ||
      readNumber(nodes[i].getAttribute('data-col')) ||
      readNumber(style.gridColumnStart) || 1;
    var start = readNumber(nodes[i].getAttribute('data-start')) ||
      readNumber(nodes[i].getAttribute('data-row')) ||
      readNumber(style.gridRowStart) || 1;
    var end = readNumber(nodes[i].getAttribute('data-end')) || start + 1;
    courses.push(safeJoin([chunks[0], day, start + '-' + end, chunks[2] || '', chunks[1] || '', chunks[3] || '']));
  }
  return courses;
}

function runTableProvider(options) {
  try {
    var table = null;
    for (var s = 0; s < options.selectors.length && !table; s++) {
      table = document.querySelector(options.selectors[s]);
    }
    if (!table) {
      var tables = document.getElementsByTagName('table');
      for (var i = 0; i < tables.length; i++) {
        var txt = tables[i].innerText || tables[i].textContent || '';
        if (txt.indexOf('星期') !== -1 || txt.indexOf('节次') !== -1) {
          table = tables[i];
          break;
        }
      }
    }
    if (!table) {
      var domCourses = coursesFromFloatingItems();
      if (domCourses.length > 0) return publishCourses(domCourses);
      return publishError(options.missingMessage);
    }

    var grid = parseTableToGrid(table);
    var courses = [];
    for (var r = 1; r < grid.length; r++) {
      if (!grid[r]) continue;
      for (var c = 1; c <= 7; c++) {
        var cell = grid[r][c];
        if (!cell || !cell.isOrigin || isBlank(cell.text)) continue;
        var blocks = splitCourseBlocks(cell.html);
        for (var b = 0; b < blocks.length; b++) {
          var chunks = textChunks(blocks[b]);
          if (chunks.length < 1) continue;
          var course = courseFromChunks(chunks, c, r, cell.rowspan);
          if (course) courses.push(course);
        }
      }
    }
    publishCourses(courses);
  } catch (e) {
    publishError(e.message);
  }
}
