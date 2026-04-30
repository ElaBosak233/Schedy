(function() {
  try {
    var courses = [];
    var items = document.querySelectorAll('.course-item, .kc-item, .schedule-item');
    for (var i = 0; i < items.length; i++) {
      var chunks = textChunks(items[i].innerHTML);
      if (chunks.length === 0) continue;
      courses.push(safeJoin([
        chunks[0] || '超星课程',
        readNumber(items[i].getAttribute('data-day')) || 1,
        (readNumber(items[i].getAttribute('data-start')) || 1) + '-' + (readNumber(items[i].getAttribute('data-end')) || 2),
        chunks[2] || '',
        chunks[1] || '',
        chunks[3] || ''
      ]));
    }
    if (courses.length === 0) publishError('超星 DOM 需针对不同高校结构微调适配');
    else document.title = 'KEBIAO_OK:HTML|' + courses.join('|');
  } catch (e) {
    publishError(e.message);
  }
})();
