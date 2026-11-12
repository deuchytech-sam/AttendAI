import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  matchLegacyLecturer,
  normalizeLecturerName,
  planCourseLecturerMigration,
} from './course_lecturer_matching.mjs';

describe('legacy course lecturer matching', () => {
  const lecturers = [
    { uid: 'lecturer-1', displayName: '  Ada   Lovelace ' },
    { uid: 'lecturer-2', displayName: 'Grace Hopper' },
    { uid: 'lecturer-3', displayName: 'ada lovelace' },
  ];

  it('normalizes case and repeated whitespace before matching', () => {
    assert.equal(normalizeLecturerName(' ADA   LOVELACE '), 'ada lovelace');
    assert.deepEqual(matchLegacyLecturer(' Grace HOPPER ', lecturers), {
      status: 'matched',
      lecturerIds: ['lecturer-2'],
    });
  });

  it('reports ambiguous and unmatched names without guessing', () => {
    assert.equal(matchLegacyLecturer('Ada Lovelace', lecturers).status, 'ambiguous');
    assert.equal(matchLegacyLecturer('Unknown Lecturer', lecturers).status, 'unmatched');
    assert.equal(matchLegacyLecturer('Unassigned', lecturers).status, 'unmatched');
  });

  it('never overwrites a non-empty lecturerIds list', () => {
    assert.deepEqual(
      planCourseLecturerMigration(
        { lecturer: 'Grace Hopper', lecturerIds: ['existing-uid'] },
        lecturers,
      ),
      { status: 'already-assigned', lecturerIds: ['existing-uid'] },
    );
    assert.equal(
      planCourseLecturerMigration(
        { lecturer: 'Grace Hopper', lecturerIds: 'legacy-invalid-value' },
        lecturers,
      ).status,
      'already-assigned',
    );
  });
});
