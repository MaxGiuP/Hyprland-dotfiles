// Pure rendering tests: no caption worker, capture, or network access.
// Run: node --test scripts/tests/caption_segments.test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const utils = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../../services/CaptionSegmentUtils.js'), 'utf8')
    .replace(/^\.pragma library\s*/, ''), utils);
const light = ['#3156a6', '#6a3e99', '#8c2c69', '#875200', '#17673b', '#076678'];
const dark = ['#a8c7fa', '#d0bcff', '#f2b8da', '#ffd180', '#a5d6a7', '#80deea'];
const pair = id => ({ id: `sentence-${id}`, source: `Source ${id}.`, translated: `Translation ${id}.`, pending: false });
const sanitize = payload => utils.sanitizeSegments(payload, 6);
const markup = (payload, translated = false, palette = light, background = '#f7f2fa', neutral = '#1d1b20') =>
    utils.markup(sanitize(payload), translated, palette, background, neutral, 4.5);
const renderedColors = html => Array.from(html.matchAll(/color:(#[0-9a-f]+);/g), match => match[1]);

test('both panes use the same six most recent sentence pairs in original order', () => {
    const input = Array.from({ length: 9 }, (_, index) => pair(index));
    const source = markup(input);
    const translated = markup(input, true);
    assert.equal(utils.plainText(sanitize(input), false), 'Source 3.\nSource 4.\nSource 5.\nSource 6.\nSource 7.\nSource 8.');
    assert.deepEqual(renderedColors(source), renderedColors(translated));
    assert.equal(new Set(renderedColors(source)).size, 6);
    assert.equal(input[0].source, 'Source 0.', 'input is not mutated');
});

test('sentence colour remains tied to its ID after reorder and removal', () => {
    const original = [pair(7), pair(8), pair(9)];
    const colors = renderedColors(markup(original));
    assert.deepEqual(renderedColors(markup([original[2], original[0]])), [colors[2], colors[0]]);
    assert.equal(utils.colorForId('a-stable-id', light, '#f7f2fa', 4.5),
        utils.colorForId('a-stable-id', light, '#f7f2fa', 4.5));
});

test('pending or missing translations are neutral and never show stale paired text', () => {
    const input = [pair(0), { ...pair(1), pending: true, translated: 'stale result' }, { ...pair(2), translated: '' }];
    const source = markup(input);
    const translated = markup(input, true);
    assert.equal(renderedColors(source)[1], '#1d1b20');
    assert.equal(renderedColors(source)[2], '#1d1b20');
    assert.equal(renderedColors(translated).length, 1);
    assert.doesNotMatch(source + translated, /stale result/);
    assert.equal(utils.plainText(sanitize(input), true), 'Translation 0.');
    assert.equal(markup([{ ...pair(1), pending: true }], true), '');
});

test('malformed pairs are rejected and newest duplicate IDs supersede old completed results', () => {
    assert.equal(sanitize(null).length, 0);
    const input = [pair(1), null, 'invalid', { id: 2, source: 'invalid' },
        { ...pair(1), source: 'Latest source', pending: true }, { id: 'empty', source: ' ' }];
    const result = sanitize({ translation_segments: input });
    assert.equal(result.length, 1);
    assert.equal(result[0].source, 'Latest source');
    assert.equal(result[0].translated, '');
    assert.equal(sanitize([{ ...pair(1), pending: 'false' }])[0].pending, true);
});

test('markup escapes untrusted HTML, quotes, and ampersands while preserving newlines', () => {
    const input = [{ id: '<script>1', source: '<img src="x"> & \'quoted\'\nnext',
        translated: '<b>literal</b>\r\nline', pending: false }];
    assert.match(markup(input), /&lt;img src=&quot;x&quot;&gt; &amp; &#39;quoted&#39;<br>next/);
    assert.match(markup(input, true), /&lt;b&gt;literal&lt;\/b&gt;<br>line/);
    assert.doesNotMatch(markup(input), /<img|<script>/);
});

test('theme palettes and adaptive colours preserve text contrast', () => {
    for (const [palette, background] of [[light, '#f7f2fa'], [dark, '#1c1b1c']]) {
        for (let index = 0; index < 6; index++) {
            const normal = utils.colorForId(`sentence-${index}`, palette, background, 4.5);
            const accessible = utils.colorForId(`sentence-${index}`, palette, background, 7);
            assert.ok(utils.contrastRatio(normal, background) >= 4.5);
            assert.ok(utils.contrastRatio(accessible, background) >= 7);
        }
    }
    for (const background of ['#777777', '#eeeeee', '#222222', '#804010']) {
        for (const candidate of light.concat(dark))
            assert.ok(utils.contrastRatio(utils.contrastAdjustedColor(candidate, background, 4.5), background) >= 4.5);
    }
    assert.notEqual(markup([pair(1)]), markup([pair(1)], false, dark, '#1c1b1c', '#e6e1e1'));
});
