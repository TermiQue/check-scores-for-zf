import unittest

from zfcheck.model import (
    diff_snapshots,
    format_full_snapshot,
    format_initial_snapshot,
    normalize_courses,
)


class ModelTests(unittest.TestCase):
    def test_detects_added_and_changed_courses(self):
        old = normalize_courses(
            [{"class_id": "1", "title": "高等数学", "grade": "80"}]
        )
        new = normalize_courses(
            [
                {"class_id": "1", "title": "高等数学", "grade": "85"},
                {"class_id": "2", "title": "大学英语", "grade": "90"},
            ]
        )
        changes = diff_snapshots(old, new)
        self.assertEqual(1, len(changes.added))
        self.assertEqual(1, len(changes.changed))
        self.assertEqual(0, len(changes.removed))

    def test_normalization_is_stable(self):
        first = normalize_courses(
            [
                {"class_id": "2", "title": "B", "grade": "90", "ignored": 1},
                {"class_id": "1", "title": "A", "grade": "80"},
            ]
        )
        second = normalize_courses(
            [
                {"class_id": "1", "title": "A", "grade": "80"},
                {"class_id": "2", "title": "B", "grade": "90", "ignored": 2},
            ]
        )
        self.assertEqual(first, second)

    def test_initial_snapshot_contains_every_course(self):
        snapshot = normalize_courses(
            [
                {"class_id": "1", "title": "高等数学", "grade": "85"},
                {"class_id": "2", "title": "大学英语", "grade": "90"},
            ]
        )

        content = format_initial_snapshot(snapshot)

        self.assertIn("当前全部成绩", content)
        self.assertIn("高等数学", content)
        self.assertIn("大学英语", content)

    def test_full_snapshot_is_newest_first_and_marks_change_types(self):
        snapshot = normalize_courses(
            [
                {
                    "class_id": "1",
                    "title": "较早课程",
                    "grade": "80",
                    "submission_time": "2026-01-01 10:00:00",
                },
                {
                    "class_id": "2",
                    "title": "最新课程",
                    "grade": "90",
                    "submission_time": "2026-07-01 10:00:00",
                },
            ]
        )

        content = format_full_snapshot(
            snapshot,
            change_types={"2": "新增", "1": "更新"},
        )

        self.assertLess(content.index("最新课程"), content.index("较早课程"))
        self.assertIn("类型：新增", content)
        self.assertIn("类型：更新", content)


if __name__ == "__main__":
    unittest.main()
