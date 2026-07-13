from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from typing import Any


SNAPSHOT_FIELDS = (
    "class_id",
    "title",
    "teacher",
    "grade",
    "percentage_grades",
    "credit",
    "xfjd",
    "submission_time",
    "name_of_submitter",
    "course_year",
    "course_semester",
)


def normalize_course(course: dict[str, Any]) -> dict[str, Any]:
    return {field: course.get(field) for field in SNAPSHOT_FIELDS}


def course_key(course: dict[str, Any]) -> str:
    class_id = str(course.get("class_id") or "").strip()
    if class_id:
        return class_id
    parts = (
        course.get("course_year"),
        course.get("course_semester"),
        course.get("title"),
        course.get("teacher"),
    )
    return "|".join(str(part or "") for part in parts)


def normalize_courses(courses: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for raw_course in courses:
        course = normalize_course(raw_course)
        result[course_key(course)] = course
    return dict(sorted(result.items()))


def snapshot_hash(snapshot: dict[str, dict[str, Any]]) -> str:
    payload = json.dumps(snapshot, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class Changes:
    added: list[dict[str, Any]]
    changed: list[tuple[dict[str, Any], dict[str, Any]]]
    removed: list[dict[str, Any]]

    @property
    def has_changes(self) -> bool:
        return bool(self.added or self.changed or self.removed)


def diff_snapshots(
    old: dict[str, dict[str, Any]], new: dict[str, dict[str, Any]]
) -> Changes:
    added = [new[key] for key in sorted(new.keys() - old.keys())]
    removed = [old[key] for key in sorted(old.keys() - new.keys())]
    changed = [
        (old[key], new[key])
        for key in sorted(old.keys() & new.keys())
        if old[key] != new[key]
    ]
    return Changes(added=added, changed=changed, removed=removed)


def display_grade(course: dict[str, Any]) -> str:
    grade = course.get("grade")
    percentage = course.get("percentage_grades")
    if grade in (None, ""):
        return str(percentage or "未知")
    if percentage not in (None, "") and str(percentage) != str(grade):
        return f"{grade}（百分制 {percentage}）"
    return str(grade)


def _course_lines(course: dict[str, Any]) -> list[str]:
    lines = [
        f"课程：{course.get('title') or '未知课程'}",
        f"成绩：{display_grade(course)}",
    ]
    if course.get("teacher"):
        lines.append(f"教师：{course['teacher']}")
    if course.get("submission_time"):
        lines.append(f"提交时间：{course['submission_time']}")
    return lines


def _course_time_key(course: dict[str, Any]) -> tuple[Any, ...]:
    raw = str(course.get("submission_time") or "").strip()
    numbers = tuple(int(value) for value in re.findall(r"\d+", raw))
    return (
        bool(raw),
        numbers,
        raw,
        str(course.get("title") or ""),
        str(course.get("class_id") or ""),
    )


def sorted_courses(
    snapshot: dict[str, dict[str, Any]],
) -> list[tuple[str, dict[str, Any]]]:
    """Return courses from newest to oldest, with undated courses last."""
    return sorted(
        snapshot.items(),
        key=lambda item: _course_time_key(item[1]),
        reverse=True,
    )


def format_changes(changes: Changes) -> str:
    sections: list[str] = []
    for course in changes.added:
        sections.append("### 新增成绩\n" + "\n".join(_course_lines(course)))
    for old, new in changes.changed:
        sections.append(
            "### 成绩变更\n"
            + f"课程：{new.get('title') or old.get('title') or '未知课程'}\n"
            + f"原成绩：{display_grade(old)}\n"
            + f"新成绩：{display_grade(new)}"
            + (f"\n提交时间：{new['submission_time']}" if new.get("submission_time") else "")
        )
    for course in changes.removed:
        sections.append(
            "### 成绩记录消失\n"
            + f"课程：{course.get('title') or '未知课程'}\n"
            + "请登录教务系统核实是否为撤回或系统异常。"
        )
    return "\n\n---\n\n".join(sections)


def format_initial_snapshot(snapshot: dict[str, dict[str, Any]]) -> str:
    """Format every currently visible course for the first successful push."""
    sections = [f"### 当前全部成绩（{len(snapshot)} 门）"]
    for _, course in sorted_courses(snapshot):
        sections.append("\n".join(_course_lines(course)))
    return "\n\n---\n\n".join(sections)


def format_full_snapshot(
    snapshot: dict[str, dict[str, Any]],
    *,
    change_types: dict[str, str] | None = None,
    removed: list[dict[str, Any]] | None = None,
) -> str:
    """Format the full current grade list and annotate changed records."""
    labels = change_types or {}
    sections = [f"### 当前全部成绩（{len(snapshot)} 门，按提交时间从新到旧）"]
    for key, course in sorted_courses(snapshot):
        lines = _course_lines(course)
        if key in labels:
            lines.insert(0, f"类型：{labels[key]}")
        sections.append("\n".join(lines))

    for course in sorted(removed or [], key=_course_time_key, reverse=True):
        sections.append(
            "类型：移除\n"
            + "\n".join(_course_lines(course))
            + "\n说明：该记录已不在本次成绩列表中，请登录教务系统核实。"
        )
    return "\n\n---\n\n".join(sections)
