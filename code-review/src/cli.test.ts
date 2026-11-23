import assert from 'node:assert/strict';
import test from 'node:test';
import { addedLines, linkedIssues, normalize, reviewMarker } from './cli.js';

test('added lines in multiple hunks are the only valid inline locations', () => {
  const patch = '@@ -2,3 +2,4 @@\n context\n-old\n+new\n+next\n context\n@@ -20,1 +21,1 @@\n-old\n+replacement';
  assert.deepEqual([...addedLines(patch)], [3, 4, 21]);
});

test('review output discards invalid or unrelated inline findings', () => {
  const result = normalize({ summary: 'Two concerns', findings: [
    { path: 'a.ts', line: 2, severity: 'high', body: 'Real issue' },
    { path: 'a.ts', line: 1, severity: 'high', body: 'Context line' },
    { path: 'other.ts', line: 2, severity: 'high', body: 'Unchanged file' },
  ] }, [{ filename: 'a.ts', status: 'modified', changes: 1, patch: '@@ -1,1 +1,2 @@\n context\n+new' }]);
  assert.equal(result.findings.length, 1);
  assert.equal(result.findings[0]?.body, 'Real issue');
});

test('issue references and head markers are deterministic', () => {
  const issues = [
    { number: 12, title: 'Bug', body: null, html_url: '' },
    { number: 13, title: 'Other', body: null, html_url: '' },
  ];
  assert.deepEqual(linkedIssues('Fixes #12 and resolves #99', issues).map(i => i.number), [12]);
  assert.equal(reviewMarker('abc'), '<!-- mini-code-review:v1:abc -->');
});
