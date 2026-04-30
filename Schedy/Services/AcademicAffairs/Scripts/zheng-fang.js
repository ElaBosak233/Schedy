(function() {
  try {
    var xnm = '';
    var xqm = '';
    var xnmSelect = document.getElementById('xnm');
    var xqmSelect = document.getElementById('xqm');
    if (xnmSelect) xnm = xnmSelect.value;
    if (xqmSelect) xqm = xqmSelect.value;

    if (!xnm) {
      var now = new Date();
      var year = now.getFullYear();
      var month = now.getMonth() + 1;
      if (month >= 9) { xnm = year.toString(); xqm = '3'; }
      else if (month >= 2) { xnm = (year - 1).toString(); xqm = '12'; }
      else { xnm = (year - 1).toString(); xqm = '3'; }
    }

    if (window.location.href.indexOf('jwglxt') === -1) {
      document.title = 'KEBIAO_ERR:请先进入教务系统的课表查询页面后再点击导入';
      return;
    }

    var basePath = window.location.pathname;
    var kbcxIdx = basePath.indexOf('/kbcx/');
    var apiPath = '';
    if (kbcxIdx !== -1) {
      apiPath = basePath.substring(0, kbcxIdx) + '/kbcx/xskbcx_cxXsgrkb.html?gnmkdm=N253508';
    } else {
      var jwIdx = basePath.indexOf('/jwglxt/');
      if (jwIdx !== -1) {
        apiPath = basePath.substring(0, jwIdx) + '/jwglxt/kbcx/xskbcx_cxXsgrkb.html?gnmkdm=N253508';
      } else {
        apiPath = '/jwglxt/kbcx/xskbcx_cxXsgrkb.html?gnmkdm=N253508';
      }
    }

    var xhr = new XMLHttpRequest();
    xhr.open('POST', apiPath, true);
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    xhr.withCredentials = true;
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== 4) return;
      if (xhr.status !== 200) {
        document.title = 'KEBIAO_ERR:请求失败 (HTTP ' + xhr.status + ')';
        return;
      }
      try {
        var resp = JSON.parse(xhr.responseText);
        var list = resp.kbList || [];
        if (list.length === 0) {
          document.title = 'KEBIAO_ERR:未查询到课程数据';
          return;
        }
        var parts = [];
        for (var i = 0; i < list.length; i++) {
          var c = list[i];
          parts.push([
            ((c.kcmc || '') + (c.xslxbj || '')).replace(/[~|]/g, ' '),
            c.xqj || '',
            (c.jcs || '').replace(/[~|]/g, ' '),
            (c.cdmc || '').replace(/[~|]/g, ' '),
            (c.zcd || '').replace(/[~|]/g, ' '),
            (c.xm || '').replace(/[~|]/g, ' ')
          ].join('~'));
        }
        document.title = 'KEBIAO_OK:' + parts.join('|');
      } catch (e) {
        document.title = 'KEBIAO_ERR:数据解析失败 ' + e.message;
      }
    };
    xhr.onerror = function() {
      document.title = 'KEBIAO_ERR:网络请求失败';
    };
    xhr.send('xnm=' + encodeURIComponent(xnm) + '&xqm=' + encodeURIComponent(xqm));
  } catch (e) {
    document.title = 'KEBIAO_ERR:' + e.message;
  }
})();
