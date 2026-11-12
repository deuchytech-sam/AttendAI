export function normalizeLecturerName(value) {
  return String(value ?? '').trim().replace(/\s+/g, ' ').toLocaleLowerCase('en');
}

export function matchLegacyLecturer(legacyName, lecturers) {
  const normalized = normalizeLecturerName(legacyName);
  if (!normalized || normalized === 'unassigned') {
    return { status: 'unmatched', lecturerIds: [] };
  }

  const matches = lecturers.filter(
    (lecturer) => normalizeLecturerName(lecturer.displayName) === normalized,
  );
  if (matches.length === 1) {
    return { status: 'matched', lecturerIds: [matches[0].uid] };
  }
  if (matches.length > 1) {
    return {
      status: 'ambiguous',
      lecturerIds: [],
      candidates: matches.map((lecturer) => lecturer.uid),
    };
  }
  return { status: 'unmatched', lecturerIds: [] };
}

export function planCourseLecturerMigration(course, lecturers) {
  const rawIds = course.lecturerIds;
  const existingIds = Array.isArray(course.lecturerIds)
    ? course.lecturerIds.filter((id) => typeof id === 'string' && id.length > 0)
    : [];
  if (
    existingIds.length > 0 ||
    (rawIds != null && !Array.isArray(rawIds) && String(rawIds).trim().length > 0)
  ) {
    return { status: 'already-assigned', lecturerIds: existingIds };
  }
  const match = matchLegacyLecturer(course.lecturer, lecturers);
  return { ...match, lecturerIds: match.lecturerIds };
}
