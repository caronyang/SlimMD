'use strict';
/* Node-based tests for the SlimMD markdown renderer (run: node tests/render.test.js) */

const assert = require('assert');
const { renderMarkdown } = require('../src/SlimMD/assets/preview.js');

let passed = 0;
const failures = [];

function t(name, fn) {
  try {
    fn();
    passed++;
  } catch (e) {
    failures.push(name + '\n    ' + e.message);
  }
}

function has(html, needle) {
  assert.ok(html.includes(needle), `expected to find:\n    ${needle}\n  in:\n    ${html}`);
}

function hasNot(html, needle) {
  assert.ok(!html.includes(needle), `expected NOT to find:\n    ${needle}\n  in:\n    ${html}`);
}

// ---- headings ----
t('ATX heading', () => has(renderMarkdown('# Hello'), '<h1 id="hello">Hello</h1>'));
t('ATX heading level 3', () => has(renderMarkdown('### Title ###'), '<h3 id="title">Title</h3>'));
t('setext h1', () => has(renderMarkdown('Title\n==='), '<h1 id="title">Title</h1>'));
t('setext h2', () => has(renderMarkdown('Title\n---'), '<h2 id="title">Title</h2>'));

// ---- inline ----
t('bold and italic', () => has(renderMarkdown('**bold** and *em*'), '<strong>bold</strong> and <em>em</em>'));
t('bold+italic triple', () => has(renderMarkdown('***both***'), '<strong><em>both</em></strong>'));
t('strikethrough', () => has(renderMarkdown('~~gone~~'), '<del>gone</del>'));
t('intraword underscore untouched', () => has(renderMarkdown('snake_case_word'), 'snake_case_word'));
t('underscore emphasis', () => has(renderMarkdown('_em_'), '<em>em</em>'));
t('code span escapes html', () => has(renderMarkdown('`a < b & c`'), '<code>a &lt; b &amp; c</code>'));
t('code span with backticks', () => has(renderMarkdown('`` `x` ``'), '<code>`x`</code>'));

// ---- links & images ----
t('inline link', () => has(renderMarkdown('[site](https://example.com)'), '<a href="https://example.com">site</a>'));
t('link title', () => has(renderMarkdown('[a](https://x.y "t")'), 'title="t"'));
t('relative link resolves to doc host', () => has(renderMarkdown('[n](sub/page.md)'), 'href="https://doc/sub/page.md"'));
t('relative image resolves to doc host', () => has(renderMarkdown('![i](img/pic.png)'), 'src="https://doc/img/pic.png"'));
t('parent relative image', () => has(renderMarkdown('![i](../pic.png)'), 'src="https://doc/pic.png"'));
t('image alt escapes html', () => has(renderMarkdown('![<b>x</b>](a.png)'), 'alt="&lt;b&gt;x&lt;/b&gt;"'));
t('autolink angle', () => has(renderMarkdown('<https://example.com/a>'), '<a href="https://example.com/a">'));
t('bare url autolink', () => has(renderMarkdown('see https://example.com/x for more'), '<a href="https://example.com/x">https://example.com/x</a>'));
t('www autolink', () => has(renderMarkdown('go www.example.com now'), '<a href="https://www.example.com">www.example.com</a>'));
t('mailto autolink', () => has(renderMarkdown('<me@example.com>'), 'href="mailto:me@example.com"'));
t('reference link', () => {
  const html = renderMarkdown('[click][ref]\n\n[ref]: https://example.com/r');
  has(html, '<a href="https://example.com/r">click</a>');
});
t('link label keeps markdown', () => {
  has(renderMarkdown('[**bold** link](https://a.b)'), '<a href="https://a.b"><strong>bold</strong> link</a>');
});

// ---- code blocks ----
t('fenced code with language', () => {
  const html = renderMarkdown('```js\nconst a = 1 < 2;\n```');
  has(html, '<pre><code class="language-js">');
  has(html, 'const a = 1 &lt; 2;');
});
t('fenced code keeps blank lines', () => {
  const html = renderMarkdown('```\na\n\nb\n```');
  has(html, 'a\n\nb\n');
});
t('indented code block', () => {
  const html = renderMarkdown('para\n\n    code line\n    second');
  has(html, '<pre><code>code line\nsecond\n</code></pre>');
});
t('tilde fence', () => has(renderMarkdown('~~~\nx\n~~~'), '<pre><code>x'));

// ---- lists ----
t('tight unordered list', () => {
  const html = renderMarkdown('- one\n- two');
  has(html, '<ul><li>one</li><li>two</li></ul>');
  hasNot(html, '<p>');
});
t('nested list', () => {
  const html = renderMarkdown('- a\n  - b\n  - c\n- d');
  has(html, '<li>a\n<ul><li>b</li><li>c</li></ul></li>');
  has(html, '<li>d</li>');
});
t('ordered list', () => {
  const html = renderMarkdown('1. one\n2. two');
  has(html, '<ol><li>one</li><li>two</li></ol>');
});
t('ordered list start', () => has(renderMarkdown('3. three\n4. four'), '<ol start="3">'));
t('task list checked', () => {
  const html = renderMarkdown('- [x] done\n- [ ] todo');
  has(html, '<li class="task"><input type="checkbox" disabled checked> done</li>');
  has(html, '<li class="task"><input type="checkbox" disabled> todo</li>');
});
t('loose list keeps paragraphs', () => {
  const html = renderMarkdown('- a\n\n- b');
  has(html, '<li><p>a</p></li>');
});
t('list marker variants', () => {
  has(renderMarkdown('* a\n* b'), '<ul><li>a</li><li>b</li></ul>');
  has(renderMarkdown('1) a\n2) b'), '<ol><li>a</li><li>b</li></ol>');
});

// ---- blockquote ----
t('blockquote', () => {
  const html = renderMarkdown('> quoted\n> text');
  has(html, '<blockquote><p>quoted text</p></blockquote>');
});
t('nested blockquote', () => {
  const html = renderMarkdown('> level1\n> > level2');
  has(html, '<blockquote><p>level1</p>');
  has(html, '<blockquote><p>level2</p></blockquote></blockquote>');
});
t('blockquote with list', () => {
  has(renderMarkdown('> - a\n> - b'), '<blockquote><ul><li>a</li><li>b</li></ul></blockquote>');
});

// ---- table ----
t('table with alignment', () => {
  const html = renderMarkdown('| Left | Center | Right |\n|:-----|:------:|------:|\n| a | b | c |');
  has(html, '<table><thead><tr><th style="text-align:left">Left</th>');
  has(html, '<th style="text-align:center">Center</th>');
  has(html, '<th style="text-align:right">Right</th>');
  has(html, '<tbody><tr><td style="text-align:left">a</td><td style="text-align:center">b</td><td style="text-align:right">c</td></tr></tbody>');
});
t('table without outer pipes', () => {
  has(renderMarkdown('a | b\n--- | ---\n1 | 2'), '<td>1</td><td>2</td>');
});

// ---- misc blocks ----
t('thematic break', () => has(renderMarkdown('a\n\n---\n\nb'), '<hr>'));
t('hr with stars', () => has(renderMarkdown('***'), '<hr>'));
t('hard break', () => has(renderMarkdown('line one  \nline two'), 'line one<br>line two'));
t('soft break becomes space', () => has(renderMarkdown('line one\nline two'), 'line one line two'));
t('paragraph escaping', () => has(renderMarkdown('a < b'), 'a &lt; b'));
t('front matter', () => {
  const html = renderMarkdown('---\ntitle: x\n---\n\n# Hi');
  has(html, '<pre class="frontmatter">title: x</pre>');
  has(html, '<h1 id="hi">Hi</h1>');
});

// ---- security ----
t('script tag escaped', () => {
  const html = renderMarkdown('<script>alert("xss")</script>');
  has(html, '&lt;script&gt;');
  hasNot(html, '<script>');
});
t('event handler stripped from allowed tag', () => {
  const html = renderMarkdown('<img src="a.png" onerror="alert(1)">');
  has(html, '<img src="https://doc/a.png"');
  hasNot(html, 'onerror');
});
t('javascript: href dropped', () => {
  const html = renderMarkdown('<a href="javascript:alert(1)">x</a>');
  hasNot(html, 'javascript:');
});
t('javascript: markdown link dropped', () => {
  const html = renderMarkdown('[x](javascript:alert(1))');
  hasNot(html, 'javascript:');
  hasNot(html, '<a');
});
t('iframe not allowed', () => {
  const html = renderMarkdown('<iframe src="https://evil"></iframe>');
  has(html, '&lt;iframe');
  hasNot(html, '<iframe');
});
t('style attribute stripped', () => {
  const html = renderMarkdown('<p style="background:url(javascript:1)">x</p>');
  hasNot(html, 'style=');
});

// ---- robustness ----
t('empty input', () => assert.strictEqual(renderMarkdown(''), ''));
t('null input', () => assert.strictEqual(renderMarkdown(null), ''));
t('crlf normalised', () => has(renderMarkdown('# A\r\n\r\nB'), '<h1 id="a">A</h1>'));
t('unclosed fence does not hang', () => {
  const html = renderMarkdown('```js\nno end');
  has(html, 'no end');
});
t('unclosed emphasis does not hang', () => {
  const html = renderMarkdown('** never closed');
  has(html, '** never closed');
});
t('large input performance', () => {
  const line = '- item with **bold** and `code` and [link](https://a.b/c)\n';
  const doc = line.repeat(3000);
  const start = Date.now();
  const html = renderMarkdown(doc);
  const ms = Date.now() - start;
  assert.ok(html.includes('</ul>'), 'list rendered');
  assert.ok(ms < 3000, `took ${ms}ms`);
});
t('deep nesting does not blow the stack', () => {
  const doc = Array.from({ length: 60 }, (_, i) => '>'.repeat(i + 1) + ' deep').join('\n');
  const html = renderMarkdown(doc);
  assert.ok(html.includes('deep'));
});

console.log(`\n${passed} passed, ${failures.length} failed`);
if (failures.length) {
  failures.forEach((f) => console.log('  FAIL ' + f));
  process.exit(1);
}
