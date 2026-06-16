# Release analysis task

You analyze a Creative Pipeline V3 release candidate.

Return only valid compact JSON. Do not include Markdown fences or explanation.

Required JSON shape:

```json
{
  "recommended_bump": "patch",
  "current_version": "0.0.0",
  "next_version": "0.0.1",
  "summary_for_user": "一句中文概括",
  "changelog": {
    "added": [],
    "changed": [],
    "fixed": [],
    "removed": []
  },
  "risks": [],
  "should_create_git_tag": true
}
```

Version rules:

- Use `patch` for fixes, docs, validation, release tooling hardening, and small compatible changes.
- Use `minor` for new compatible user-facing features.
- Use `major` for breaking workflow, template, or architecture changes.
- Set `next_version` from `current_version` and `recommended_bump`.

Output rules:

- Write changelog and risks in Chinese.
- Keep each changelog array to at most 4 items.
- Keep each changelog item under 40 Chinese characters.
- Include risks for untracked files, deleted files, large changes, release boundary issues, or fallback uncertainty.
- Browser profiles, cookies, real product inputs, output images, logs, API keys, local tokens, node_modules, and cache directories must never be released.
