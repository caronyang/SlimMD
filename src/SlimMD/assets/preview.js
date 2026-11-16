'use strict';

/* ------------------------------------------------------------------
 * SlimMD Markdown renderer.
 * A compact CommonMark/GFM subset with no external dependencies.
 * Escapes all raw HTML except a safe whitelist of tags/attributes.
 * ------------------------------------------------------------------ */

var SLIMMD = (function () {

  // ------------------------------------------------------------ utils

  var ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) { return ESC[c]; });
  }

  function escapeAttr(s) {
    return escapeHtml(s);
  }

  var ALLOWED_TAGS = {};
  ['a', 'abbr', 'b', 'big', 'blockquote', 'br', 'caption', 'center', 'cite', 'code',
   'col', 'colgroup', 'dd', 'del', 'details', 'dfn', 'div', 'dl', 'dt', 'em', 'figcaption',
   'figure', 'font', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'i', 'img', 'ins', 'kbd',
   'li', 'mark', 'ol', 'p', 'pre', 'q', 's', 'samp', 'small', 'span', 'strike', 'strong',
   'sub', 'summary', 'sup', 'table', 'tbody', 'td', 'tfoot', 'th', 'thead', 'tr', 'tt',
   'u', 'ul', 'var'
  ].forEach(function (t) { ALLOWED_TAGS[t] = true; });

  var URL_ATTRS = { href: true, src: true };

  var TAG_RE = /<(\/?)([A-Za-z][A-Za-z0-9-]*)((?:"[^"]*"|'[^']*'|[^>"'])*?)(\/?)>/g;

  /** True when `url` may be used in href/src. Returns '' when dangerous. */
  function safeUrl(url) {
    url = String(url).trim();
    if (url === '') return '';
    if (url.charAt(0) === '#') return url;
    if (/^(https?|ftp|mailto|tel):/i.test(url)) return url;
    if (/^data:image\/(png|gif|jpe?g|webp|svg\+xml);/i.test(url)) return url;
    if (/^[a-z][a-z0-9+.\-]*:/i.test(url)) return '';   // javascript:, vbscript:, file:, ...
    if (/^\/\//.test(url)) return 'https:' + url;       // protocol relative
    return url;                                          // relative - resolved later
  }

  /** Resolve a relative path against the document root (https://doc/ = folder of the .md file). */
  function resolveUrl(url) {
    if (url === '' || url.charAt(0) === '#') return url;
    if (/^[a-z][a-z0-9+.\-]*:/i.test(url) || /^\/\//.test(url)) return url;
    var parts = url.split('/');
    var out = [];
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i];
      if (p === '.' || p === '') { if (i === 0) continue; }
      else if (p === '..') { if (out.length) out.pop(); }
      else { out.push(p.replace(/[^A-Za-z0-9\-._~!$&'()*+,;=:@%]/g, function (c) {
        return encodeURIComponent(c);
      })); }
    }
    return 'https://doc/' + out.join('/');
  }

  function attrString(attrs) {
    var s = '';
    for (var k in attrs) {
      if (!Object.prototype.hasOwnProperty.call(attrs, k)) continue;
      s += ' ' + k + '="' + escapeAttr(attrs[k]) + '"';
    }
    return s;
  }

  /** Keep an HTML tag only if whitelisted, and strip unsafe attributes. */
  function sanitizeTag(match, closing, tagName, rawAttrs, selfClose) {
    var tag = tagName.toLowerCase();
    if (closing === '/' && (tag === 'br' || tag === 'img' || tag === 'hr')) return '';
    if (!ALLOWED_TAGS[tag]) return escapeHtml(match);

    var attrs = {};
    var re = /([A-Za-z_:][-A-Za-z0-9_:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
    var m;
    while ((m = re.exec(rawAttrs)) !== null) {
      var name = m[1].toLowerCase();
      var value = m[2] !== undefined ? m[2] : (m[3] !== undefined ? m[3] : (m[4] !== undefined ? m[4] : ''));
      if (name.slice(0, 2) === 'on') continue;                 // onclick= etc.
      if (name === 'style' || name === 'srcdoc' || name === 'formaction') continue;
      if (URL_ATTRS[name]) {
        var u = safeUrl(value);
        if (u === '') continue;
        attrs[name] = resolveUrl(u);
        continue;
      }
      if (!/^(class|id|title|alt|width|height|colspan|rowspan|align|valign|start|type|checked|disabled|open|lang|dir|datetime|cite|abbr)$/.test(name)) continue;
      if (name === 'type' && tag === 'input') {
        if (value.toLowerCase() !== 'checkbox' && value.toLowerCase() !== 'radio') continue;
      }
      attrs[name] = value;
    }
    if (tag === 'a' && (attrs.target === '_blank')) attrs.rel = 'noopener';

    return '<' + (closing === '/' ? '/' : '') + tag + attrString(attrs) + (selfClose === '/' && (tag === 'br' || tag === 'img' || tag === 'hr') ? ' /' : '') + '>';
  }

  // ------------------------------------------------------------ inline

  function TokenStore() {
    this.items = [];
  }
  TokenStore.prototype.push = function (html, plain) {
    var i = this.items.length;
    this.items.push({ h: html, p: plain === undefined ? '' : plain });
    return '\u0000' + i + '\u0000';
  };
  TokenStore.prototype.plain = function (text) {
    return String(text).replace(/\u0000(\d+)\u0000/g, function (m, i) {
      return this.items[+i] ? this.items[+i].p : '';
    }.bind(this));
  };
  TokenStore.prototype.restore = function (text) {
    return String(text).replace(/\u0000(\d+)\u0000/g, function (m, i) {
      return this.items[+i] ? this.items[+i].h : '';
    }.bind(this));
  };

  /** Reference definitions are collected by the block parser. */
  function parseInline(src, tokens, refs) {
    var text = String(src);

    // 1. code spans (highest precedence)
    text = text.replace(/(`+)([\s\S]*?)\1(?!`)/g, function (m, ticks, code) {
      if (code.length > 1 && code.charAt(0) === ' ' && code.charAt(code.length - 1) === ' ' &&
          code.replace(/ /g, '') !== '') {
        code = code.slice(1, -1);
      }
      return tokens.push('<code>' + escapeHtml(code) + '</code>', code);
    });

    // 2. autolinks: <https://...> and <mail@example.com>
    text = text.replace(/<((?:https?|ftp):\/\/[^<>\s]+)>/gi, function (m, url) {
      return tokens.push('<a href="' + escapeAttr(url) + '">' + escapeHtml(url) + '</a>', url);
    });
    text = text.replace(/<([A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,})>/g, function (m, mail) {
      return tokens.push('<a href="mailto:' + escapeAttr(mail) + '">' + escapeHtml(mail) + '</a>', mail);
    });

    // 3. raw inline HTML (whitelisted only)
    text = text.replace(TAG_RE, function (m, closing, tag, attrs, selfClose) {
      return sanitizeTag(m, closing, tag, attrs, selfClose);
    });

    // 4. images  ![alt](url "title")
    text = text.replace(/!\[([^\]]*)\]\(\s*(<[^>]*>|[^\s)]*)(?:\s+["'(]([^"')]*)["')])?\s*\)/g,
      function (m, alt, url, title) {
        url = String(url).replace(/^<|>$/g, '');
        var u = safeUrl(url);
        if (u === '') return '';
        var attrs = { src: resolveUrl(u), alt: tokens.plain(alt) };
        if (title) attrs.title = title;
        return tokens.push('<img' + attrString(attrs) + '>', tokens.plain(alt));
      });

    // 5. links  [text](url "title")  /  [text][ref]  /  [text][]
    text = text.replace(/\[([^\]]*)\]\(\s*(<[^>]*>|[^\s)]*)(?:\s+["'(]([^"')]*)["')])?\s*\)/g,
      function (m, label, url, title) {
        url = String(url).replace(/^<|>$/g, '');
        var u = safeUrl(url);
        if (u === '') return tokens.restore(parseInline(label, tokens, refs));
        var attrs = { href: resolveUrl(u) };
        if (title) attrs.title = title;
        return tokens.push('<a' + attrString(attrs) + '>' + parseInline(label, tokens, refs) + '</a>',
          tokens.plain(label));
      });

    text = text.replace(/\[([^\]]+)\]\[([^\]]*)\]/g, function (m, label, ref) {
      var key = (ref || label).trim().toLowerCase();
      var def = refs && refs[key];
      if (!def) return m;
      var attrs = { href: resolveUrl(safeUrl(def.url) || '') };
      if (def.title) attrs.title = def.title;
      return tokens.push('<a' + attrString(attrs) + '>' + parseInline(label, tokens, refs) + '</a>',
        tokens.plain(label));
    });

    // 6. escape whatever is left
    text = escapeHtml(text);

    // 7. emphasis / strikethrough
    text = text.replace(/\*\*\*(?=\S)([\s\S]*?\S)\*\*\*/g, '<strong><em>$1</em></strong>');
    text = text.replace(/\*\*(?=\S)([\s\S]*?\S)\*\*/g, '<strong>$1</strong>');
    text = text.replace(/(?<![\w])__(?=\S)([\s\S]*?\S)__(?![\w])/g, '<strong>$1</strong>');
    text = text.replace(/\*(?=\S)([^*]*?\S)\*/g, '<em>$1</em>');
    text = text.replace(/(?<![\w])_(?=\S)([^_]*?\S)_(?![\w])/g, '<em>$1</em>');
    text = text.replace(/~~(?=\S)([\s\S]*?\S)~~/g, '<del>$1</del>');

    // 8. bare URLs
    text = text.replace(/(^|[\s(\[{"'])(https?:\/\/[^\s<>"']+)/g, function (m, pre, url) {
      var trailing = '';
      while (/[.,;:!?)\]]+$/.test(url) && (url.split('(').length - 1) >= (url.split(')').length - 1)) {
        var c = url.slice(-1);
        if (c === ')' && (url.split('(').length - 1) < (url.split(')').length)) break;
        trailing = c + trailing;
        url = url.slice(0, -1);
      }
      if (url === '') return m;
      return pre + '<a href="' + escapeAttr(url) + '">' + escapeHtml(url) + '</a>' + trailing;
    });
    text = text.replace(/(^|[\s(\[{"'])(www\.[^\s<>"']+)/g, function (m, pre, url) {
      var trailing = '';
      while (/[.,;:!?)\]]+$/.test(url)) { trailing = url.slice(-1) + trailing; url = url.slice(0, -1); }
      if (url === '') return m;
      var href = 'https://' + url;
      return pre + '<a href="' + escapeAttr(href) + '">' + escapeHtml(url) + '</a>' + trailing;
    });

    // 9. hard line breaks, soft line breaks, token restore
    text = text.replace(/\u0001\n/g, '<br>').replace(/\n/g, ' ');
    return tokens.restore(text);
  }

  // ------------------------------------------------------------ block helpers

  function slug(text) {
    return String(text).toLowerCase()
      .replace(/<[^>]*>/g, '')
      .replace(/[^\w\u4e00-\u9fff]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 60) || 'section';
  }

  function countIndent(line) {
    var i = 0;
    while (i < line.length && i < 4 && line.charAt(i) === ' ') i++;
    return i;
  }

  function isBlank(line) { return !line || !line.trim(); }

  function isAtxHeading(line) { return /^ {0,3}#{1,6}(\s|$)/.test(line); }

  function isFenceStart(line) { return /^ {0,3}(`{3,}|~{3,})/.test(line); }

  function isHrStar(line) { return /^ {0,3}([*_])([ \t]*\1){2,}[ \t]*$/.test(line); }

  function isSetextUnderline(line) { return /^ {0,3}(={1,}|-{1,})[ \t]*$/.test(line); }

  function matchListItem(line) {
    var m = /^ {0,3}([-*+]|(\d{1,9})([.)]))([ \t]+|$)(.*)$/.exec(line);
    if (!m) return null;
    var ordered = m[2] !== undefined;
    var rest = m[5];
    var markerEnd = m[0].length - rest.length;
    var contentIndent = markerEnd;   // column where the item content begins
    return {
      ordered: ordered,
      num: ordered ? parseInt(m[2], 10) : 0,
      delim: ordered ? m[3] : m[1],
      marker: m[1],
      rest: rest,
      contentIndent: contentIndent
    };
  }

  function isListStart(line) { return matchListItem(line) !== null; }

  function isBlockquote(line) { return /^ {0,3}>/.test(line); }

  function isHtmlBlockStart(line) {
    return /^ {0,3}<\/?[A-Za-z][A-Za-z0-9-]*(?=[\s/>])/.test(line) &&
           !/^ {0,3}<(?:https?|ftp|mailto):/i.test(line);
  }

  function isBlockStart(line) {
    return isAtxHeading(line) || isFenceStart(line) || isHrStar(line) ||
           isBlockquote(line) || isListStart(line) || isHtmlBlockStart(line);
  }

  // ------------------------------------------------------------ tables

  function splitRow(row) {
    var s = String(row).trim();
    if (s.charAt(0) === '|') s = s.slice(1);
    if (s.charAt(s.length - 1) === '|' && s.charAt(s.length - 2) !== '\\') s = s.slice(0, -1);
    var cells = [], cur = '';
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i);
      if (c === '\\' && s.charAt(i + 1) === '|') { cur += '|'; i++; continue; }
      if (c === '|') { cells.push(cur); cur = ''; continue; }
      cur += c;
    }
    cells.push(cur);
    return cells.map(function (c) { return c.trim(); });
  }

  function isTableDelimiter(line) {
    if (!line || line.indexOf('-') < 0) return false;
    if (!/^ {0,3}\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$/.test(line.trim())) return false;
    return splitRow(line).length > 0;
  }

  function renderTable(headerLine, delimLine, bodyLines, ctx) {
    var headers = splitRow(headerLine);
    var delims = splitRow(delimLine);
    var aligns = delims.map(function (d) {
      var t = d.trim();
      var l = t.charAt(0) === ':', r = t.charAt(t.length - 1) === ':';
      if (l && r) return 'center';
      if (r) return 'right';
      if (l) return 'left';
      return '';
    });
    var tokens = new TokenStore();

    function row(cells, tag) {
      var html = '<tr>';
      for (var i = 0; i < headers.length; i++) {
        var align = aligns[i] ? ' style="text-align:' + aligns[i] + '"' : '';
        html += '<' + tag + align + '>' + parseInline(cells[i] === undefined ? '' : cells[i], tokens, ctx.refs) + '</' + tag + '>';
      }
      return html + '</tr>';
    }

    var html = '<table><thead>' + row(headers, 'th') + '</thead><tbody>';
    bodyLines.forEach(function (line) {
      if (!line || !line.trim()) return;
      html += row(splitRow(line), 'td');
    });
    html += '</tbody></table>';
    return html;
  }

  // ------------------------------------------------------------ lists

  function renderList(lines, start, ctx, out) {
    var first = matchListItem(lines[start]);
    var ordered = first.ordered;
    var delim = first.delim;
    var startNum = ordered ? first.num : 1;

    var items = [];
    var loose = false;
    var i = start;

    while (i < lines.length) {
      // skip blank lines between items when the list continues
      var j = i;
      while (j < lines.length && isBlank(lines[j])) j++;
      if (j > i) {
        if (j >= lines.length) break;
        var probe = matchListItem(lines[j]);
        if (!probe || probe.ordered !== ordered || probe.delim !== delim || countIndent(lines[j]) > 3) break;
        loose = true;
        i = j;
      }

      var m = matchListItem(lines[i]);
      if (!m || m.ordered !== ordered || m.delim !== delim) break;

      var contentIndent = m.contentIndent;
      var buf = [m.rest];
      var itemLoose = false;
      i++;

      while (i < lines.length) {
        var line = lines[i];

        if (isBlank(line)) {
          var k = i;
          while (k < lines.length && isBlank(lines[k])) k++;
          if (k >= lines.length) { i = lines.length; break; }
          var after = lines[k];
          var afterIndent = countIndent(after);
          var afterItem = matchListItem(after);
          var continues = afterIndent >= contentIndent ||
            (afterItem && afterItem.ordered === ordered && afterItem.delim === delim && afterIndent < contentIndent && afterIndent <= 3);
          if (!continues) break;               // blank line ends the list
          if (afterItem && afterIndent < contentIndent) { break; }  // next item handled by outer loop
          itemLoose = true;
          loose = true;
          for (; i < k; i++) buf.push('');
          continue;
        }

        var indent = countIndent(line);
        var item = matchListItem(line);

        if (indent >= contentIndent) {
          buf.push(line.slice(Math.min(indent, contentIndent)));
          i++;
          continue;
        }

        if (item && indent <= 3) break;        // sibling item

        if (!isBlockStart(line)) { buf.push(line); i++; continue; }  // lazy continuation
        break;
      }

      items.push({ buf: buf, loose: itemLoose });
      if (itemLoose) loose = true;
    }

    if (items.length === 0) { out.push(''); return start; }

    // Task list?
    var isTask = items.some(function (it) {
      return /^\[[ xX]\]([ \t]|$)/.test(it.buf[0] || '');
    });

    var tag = ordered ? 'ol' : 'ul';
    var open = '<' + tag + (ordered && startNum !== 1 ? ' start="' + startNum + '"' : '') + '>';
    var html = open;

    items.forEach(function (it) {
      var taskChecked = false;
      var first = it.buf[0] || '';
      var tm = /^\[([ xX])\]([ \t]|$)/.exec(first);
      if (tm && isTask) {
        taskChecked = tm[1] !== ' ';
        it.buf[0] = first.slice(tm[0].length);
      }

      var content = it.buf.join('\n');
      var rendered;
      if (isBlank(content)) {
        rendered = '';
      } else {
        rendered = renderBlocks(content.split('\n'), ctx, !loose);
      }

      if (tm && isTask) {
        html += '<li class="task"><input type="checkbox" disabled' +
          (taskChecked ? ' checked' : '') + '> ' + rendered + '</li>';
      } else {
        html += '<li>' + rendered + '</li>';
      }
    });

    html += '</' + tag + '>';
    out.push(html);
    return i;
  }

  // ------------------------------------------------------------ blocks

  function joinParagraph(buf) {
    return buf.map(function (line, idx) {
      if (idx === buf.length - 1) return line;
      var m = /^(.*?)([ \t]{2,})$/.exec(line);
      return m ? m[1] + '\u0001' : line;
    }).join('\n');
  }

  function renderBlocks(lines, ctx, tight) {
    tight = !!tight;
    var out = [];
    var i = 0;
    var n = lines.length;
    var tokens = new TokenStore();

    while (i < n) {
      var line = lines[i];

      if (isBlank(line)) { i++; continue; }

      // fenced code block
      var m = /^ {0,3}(`{3,}|~{3,})[ \t]*([^\s`]*)[ \t]*$/.exec(line);
      if (m) {
        var fence = m[1];
        var lang = m[2];
        var closeRe = new RegExp('^ {0,3}' + (fence.charAt(0) === '`' ? '`' : '~') + '{' + fence.length + ',}[ \\t]*$');
        var buf = [];
        i++;
        while (i < n && !closeRe.test(lines[i])) { buf.push(lines[i]); i++; }
        if (i < n) i++;
        var cls = lang ? ' class="language-' + escapeAttr(lang.replace(/[^\w+#\-.]/g, '')) + '"' : '';
        out.push('<pre><code' + cls + '>' + escapeHtml(buf.join('\n')) + (buf.length ? '\n' : '') + '</code></pre>');
        continue;
      }

      // ATX heading
      m = /^ {0,3}(#{1,6})[ \t]+(.*?)[ \t]*$/.exec(line);
      if (m) {
        var level = m[1].length;
        var htext = m[2].replace(/[ \t]+#+[ \t]*$/, '');
        out.push('<h' + level + ' id="' + escapeAttr(slug(htext)) + '">' +
          parseInline(htext, tokens, ctx.refs) + '</h' + level + '>');
        i++;
        continue;
      }

      // thematic break
      if (/^ {0,3}([-*_])([ \t]*\1){2,}[ \t]*$/.test(line)) {
        out.push('<hr>');
        i++;
        continue;
      }

      // blockquote
      if (isBlockquote(line)) {
        var qbuf = [];
        while (i < n) {
          if (isBlockquote(lines[i])) {
            qbuf.push(lines[i].replace(/^ {0,3}>[ \t]?/, ''));
            i++;
            continue;
          }
          if (!isBlank(lines[i]) && !isBlockStart(lines[i]) && qbuf.length && !isSetextUnderline(lines[i])) {
            qbuf.push(lines[i]);   // lazy continuation
            i++;
            continue;
          }
          break;
        }
        out.push('<blockquote>' + renderBlocks(qbuf, ctx, false) + '</blockquote>');
        continue;
      }

      // list
      if (isListStart(line)) {
        i = renderList(lines, i, ctx, out);
        continue;
      }

      // table (header row followed by a delimiter row)
      if (line.indexOf('|') >= 0 && i + 1 < n && isTableDelimiter(lines[i + 1])) {
        var delimLine = lines[i + 1];
        var body = [];
        i += 2;
        while (i < n && lines[i].indexOf('|') >= 0 && !isBlank(lines[i]) && !isBlockStart(lines[i])) {
          body.push(lines[i]);
          i++;
        }
        out.push(renderTable(line, delimLine, body, ctx));
        continue;
      }

      // indented code block
      if (/^(?: {4}|\t)/.test(line)) {
        var cbuf = [];
        while (i < n) {
          if (isBlank(lines[i])) {
            var k = i;
            while (k < n && isBlank(lines[k])) k++;
            if (k >= n || !/^(?: {4}|\t)/.test(lines[k])) break;
            for (; i < k; i++) cbuf.push('');
            continue;
          }
          if (!/^(?: {4}|\t)/.test(lines[i])) break;
          cbuf.push(lines[i].replace(/^(?: {4}|\t)/, ''));
          i++;
        }
        out.push('<pre><code>' + escapeHtml(cbuf.join('\n')) + '\n</code></pre>');
        continue;
      }

      // raw HTML block (sanitised)
      if (isHtmlBlockStart(line)) {
        var hbuf = [];
        while (i < n && !isBlank(lines[i])) { hbuf.push(lines[i]); i++; }
        out.push(sanitizeHtmlBlock(hbuf.join('\n')));
        continue;
      }

      // paragraph (with setext heading detection)
      var pbuf = [];
      while (i < n && !isBlank(lines[i])) {
        var cur = lines[i];
        if (isBlockStart(cur)) break;
        if (isSetextUnderline(cur) && pbuf.length) break;
        if (pbuf.length && cur.indexOf('|') >= 0 && i + 1 < n && isTableDelimiter(lines[i + 1])) break;
        pbuf.push(cur);
        i++;
      }

      if (pbuf.length === 0) { i++; continue; }

      if (i < n && isSetextUnderline(lines[i]) && /^[ \t]*=/.test(lines[i])) {
        var h1 = joinParagraph(pbuf);
        out.push('<h1 id="' + escapeAttr(slug(h1)) + '">' + parseInline(h1, tokens, ctx.refs) + '</h1>');
        i++;
        continue;
      }
      if (i < n && isSetextUnderline(lines[i]) && /^[ \t]*-/.test(lines[i])) {
        var h2 = joinParagraph(pbuf);
        out.push('<h2 id="' + escapeAttr(slug(h2)) + '">' + parseInline(h2, tokens, ctx.refs) + '</h2>');
        i++;
        continue;
      }

      var para = parseInline(joinParagraph(pbuf), tokens, ctx.refs);
      out.push(tight ? para : '<p>' + para + '</p>');
    }

    return out.join('\n');
  }

  /** Escape everything except whitelisted (and attribute-sanitised) tags. */
  function sanitizeHtmlBlock(text) {
    var store = new TokenStore();
    var protected1 = String(text).replace(TAG_RE, function (m, closing, tag, attrs, selfClose) {
      if (!ALLOWED_TAGS[tag.toLowerCase()]) return m;   // escaped below
      return store.push(sanitizeTag(m, closing, tag, attrs, selfClose), '');
    });
    protected1 = protected1.replace(/[<>]/g, function (c) { return c === '<' ? '&lt;' : '&gt;' });
    return store.restore(protected1);
  }

  // ------------------------------------------------------------ entry point

  function renderMarkdown(src) {
    if (src === null || src === undefined) src = '';
    var text = String(src).replace(/\r\n?/g, '\n');
    var lines = text.split('\n');

    // YAML / TOML front matter at the very top
    var front = '';
    if (lines.length > 1 && /^(---|\+\+\+)[ \t]*$/.test(lines[0])) {
      for (var f = 1; f < Math.min(lines.length, 500); f++) {
        if (/^(---|\+\+\+|\.\.\.)[ \t]*$/.test(lines[f])) {
          front = '<pre class="frontmatter">' + escapeHtml(lines.slice(1, f).join('\n')) + '</pre>';
          lines = lines.slice(f + 1);
          break;
        }
        if (f === 1 && /^(---|\+\+\+)[ \t]*$/.test(lines[0]) === false) break;
      }
    }

    // reference-style link definitions
    var refs = Object.create(null);
    var body = [];
    var inFence = false;
    var fenceChar = '';
    var fenceLen = 0;
    for (var i = 0; i < lines.length; i++) {
      var l = lines[i];
      var fm = /^ {0,3}(`{3,}|~{3,})/.exec(l);
      if (fm) {
        if (!inFence) { inFence = true; fenceChar = fm[1].charAt(0); fenceLen = fm[1].length; }
        else if (fm[1].charAt(0) === fenceChar && fm[1].length >= fenceLen) { inFence = false; }
        body.push(l);
        continue;
      }
      if (!inFence) {
        var def = /^ {0,3}\[([^\]]+)\]:[ \t]*(\S+)(?:[ \t]+["'(](.*)["')])?[ \t]*$/.exec(l);
        if (def) {
          refs[def[1].trim().toLowerCase()] = { url: def[2], title: def[3] || '' };
          continue;
        }
      }
      body.push(l);
    }

    return front + renderBlocks(body, { refs: refs }, false);
  }

  return { renderMarkdown: renderMarkdown };
})();

if (typeof module !== 'undefined' && module.exports) {
  module.exports = SLIMMD;
}

if (typeof window !== 'undefined' && window.addEventListener) {
  window.addEventListener('error', function (e) {
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage({ type: 'jserror', message: String(e.message), line: e.lineno });
    }
  });
  window.addEventListener('message', function (event) {
    var data = event.data;
    if (!data || data.type !== 'render') return;
    try {
      var el = document.getElementById('content');
      if (!el) return;
      el.innerHTML = SLIMMD.renderMarkdown(data.markdown || '');
      if (data.reset) window.scrollTo(0, 0);
    } catch (err) {
      if (window.chrome && window.chrome.webview) {
        window.chrome.webview.postMessage({ type: 'jserror', message: String(err && err.stack || err) });
      }
    }
  });

  // Forward app shortcuts to the host. With AreBrowserAcceleratorKeysEnabled=false
  // Chromium delivers these keys to the page instead of handling them, and the
  // WinForms OnKeyDown never fires while the preview has focus (browse view).
  window.addEventListener('keydown', function (e) {
    if (!window.chrome || !window.chrome.webview) return;
    var k = e.key;
    var ctrl = e.ctrlKey;
    var shift = e.shiftKey;
    var action = null;
    if (ctrl && !shift && (k === 'n' || k === 'N')) action = 'new';
    else if (ctrl && !shift && (k === 'o' || k === 'O')) action = 'open';
    else if (ctrl && (k === 's' || k === 'S')) action = shift ? 'saveas' : 'save';
    else if (ctrl && !shift && (k === 'e' || k === 'E')) action = 'toggle';
    else if (!ctrl && k === 'F9') action = 'toggle';
    if (!action) return;
    e.preventDefault();
    window.chrome.webview.postMessage({ type: 'shortcut', action: action });
  });

  // Report the preview scroll position to the host so it can follow the
  // editor (and vice versa). Throttled to one message per animation frame.
  var scrollPending = false;
  window.addEventListener('scroll', function () {
    if (syncing || scrollPending) return;
    if (!window.chrome || !window.chrome.webview) return;
    scrollPending = true;
    window.requestAnimationFrame(function () {
      scrollPending = false;
      try {
        window.chrome.webview.postMessage({ type: 'scroll', ratio: SLIMMD.scrollRatio() });
      } catch (err) { /* host gone */ }
    });
  }, { passive: true });

  // Tell the host that the listener is registered and ready for content.
  if (window.chrome && window.chrome.webview) {
    window.chrome.webview.postMessage({ type: 'ready' });
  }
}

/** Set while the host is driving the preview scroll, to swallow the echo. */
var syncing = false;

/** Render entry point called by the host through ExecuteScriptAsync. */
SLIMMD.apply = function (markdown, reset) {
  var el = document.getElementById('content');
  if (!el) return;
  el.innerHTML = SLIMMD.renderMarkdown(markdown || '');
  if (reset) window.scrollTo(0, 0);
};

/** Scroll position of the preview as a 0..1 fraction of the scrollable range. */
SLIMMD.scrollRatio = function () {
  var max = document.documentElement.scrollHeight - window.innerHeight;
  if (max <= 0) return 0;
  var r = window.scrollY / max;
  return r < 0 ? 0 : (r > 1 ? 1 : r);
};

/** Scroll the preview to a 0..1 fraction. Used by the host to follow the editor. */
SLIMMD.scrollToRatio = function (ratio) {
  var max = document.documentElement.scrollHeight - window.innerHeight;
  if (max <= 0) return;
  var r = ratio < 0 ? 0 : (ratio > 1 ? 1 : ratio);
  // Suppress the scroll event this generates so it does not echo back to the host.
  syncing = true;
  window.scrollTo(0, r * max);
  window.setTimeout(function () { syncing = false; }, 120);
};
