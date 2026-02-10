import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeMarkdownForPersistence } from '../src/markdown-normalization.mjs';

test('repairs escaped task markers followed by paragraph content', () => {
  const input = [
    '- \\[x\\]',
    '',
    '  <p style="text-align: center"> Task List</p>',
    '',
    '  <p></p>',
    '',
    '- \\[ \\]',
    '',
    '  <p style="text-align: center"> Needs work &amp; review</p>',
    '',
    '  <p></p>',
  ].join('\n');

  const output = normalizeMarkdownForPersistence(input);
  assert.equal(output, '- [x] Task List\n- [ ] Needs work & review');
});

test('repairs inline task paragraph form and normalizes spacing', () => {
  const input = [
    '- [x] <p style="text-align: center"> Ready </p>',
    '- [ ]     Waiting',
  ].join('\n');

  const output = normalizeMarkdownForPersistence(input);
  assert.equal(output, '- [x] Ready\n- [ ] Waiting');
});

test('keeps fenced code blocks untouched', () => {
  const input = [
    '```md',
    '- [x]     should stay as-is in code',
    '- \\[x\\]',
    '```',
    '',
    '- [x]     should normalize',
  ].join('\n');

  const output = normalizeMarkdownForPersistence(input);
  assert.equal(output, [
    '```md',
    '- [x]     should stay as-is in code',
    '- \\[x\\]',
    '```',
    '',
    '- [x] should normalize',
  ].join('\n'));
});

test('does not alter non-task list items', () => {
  const input = [
    '- regular bullet',
    '- [ ]',
    '1. normal ordered item',
    '',
    '<p style="text-align: center">Paragraph</p>',
  ].join('\n');

  const output = normalizeMarkdownForPersistence(input);
  assert.equal(output, input);
});

test('repairs escaped hard break lines inside html paragraphs', () => {
  const input = [
    '<p style="text-align: center">\\\\',
    '\\\\',
    'Testing gaps.</p>',
  ].join('\n');

  const output = normalizeMarkdownForPersistence(input);
  assert.equal(output, [
    '<p style="text-align: center"><br />',
    '<br />',
    'Testing gaps.</p>',
  ].join('\n'));
});

test('keeps inline escaped backslashes inside html paragraph text', () => {
  const input = '<p style="text-align: center">Not sure what\\\'s up with the \\\\ all over.</p>';
  const output = normalizeMarkdownForPersistence(input);
  assert.equal(output, input);
});

test('repairs marker-only task items followed by indented plain text', () => {
  const input = [
    '- [x]',
    '',
    '  Task List',
    '',
    '- [ ]',
    '',
    '  Needs follow up',
  ].join('\n');

  const output = normalizeMarkdownForPersistence(input);
  assert.equal(output, '- [x] Task List\n- [ ] Needs follow up');
});

test('keeps intentionally empty task items when continuation is not indented', () => {
  const input = [
    '- [ ]',
    '',
    'This paragraph should stay separate.',
  ].join('\n');

  const output = normalizeMarkdownForPersistence(input);
  assert.equal(output, input);
});
