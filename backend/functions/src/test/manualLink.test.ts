import assert from 'node:assert/strict';
import { test } from 'node:test';

import { shouldPropagateManualLink } from '../manualLink.js';

const linked = { linkedUid: 'uid-marta' };

test('el filtro del trigger acepta solo el alta inicial', () => {
  assert.equal(shouldPropagateManualLink(undefined, linked), true);
  assert.equal(
    shouldPropagateManualLink({ linkedUid: null }, linked),
    true,
  );
  assert.equal(
    shouldPropagateManualLink({ linkedUid: 'uid-marta' }, linked),
    false,
  );
});

test('las escrituras terminales y sus metadatos no realimentan el trigger', () => {
  assert.equal(
    shouldPropagateManualLink(linked, { ...linked, linkStatus: 'processing' }),
    false,
  );
  assert.equal(
    shouldPropagateManualLink(
      { ...linked, linkStatus: 'processing' },
      { ...linked, linkStatus: 'active', linkPropagatedSessions: 2 },
    ),
    false,
  );
  assert.equal(
    shouldPropagateManualLink(
      { ...linked, linkStatus: 'processing' },
      { ...linked, linkStatus: 'failed', linkError: 'propagation-error' },
    ),
    false,
  );
  assert.equal(
    shouldPropagateManualLink(
      { ...linked, linkStatus: 'active' },
      { ...linked, linkStatus: 'active', linkPropagatedAt: 'same' },
    ),
    false,
  );
});

test('failed -> processing es la única entrada de reintento', () => {
  assert.equal(
    shouldPropagateManualLink(
      { ...linked, linkStatus: 'failed' },
      {
        ...linked,
        linkStatus: 'processing',
        linkError: 'propagation-error',
      },
    ),
    true,
  );
  assert.equal(
    shouldPropagateManualLink(
      { ...linked, linkStatus: 'failed' },
      { ...linked, linkStatus: 'active' },
    ),
    false,
  );
  assert.equal(
    shouldPropagateManualLink(
      { ...linked, linkStatus: 'processing' },
      { ...linked, linkStatus: 'processing' },
    ),
    false,
  );
  assert.equal(shouldPropagateManualLink(linked, undefined), false);
});
