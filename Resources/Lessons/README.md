# Resources/Lessons

**除了这个文件，目录是空的才正常。** 练习页由 `sync-lessons.sh` 在每次构建前
从 `~/Edu` 组装进来（`~/Edu/engine/app_pack.py`：剥会话 chrome → 过与上线同一道
PII 门 → 写 manifest.json）。

SSOT 在 `~/Edu`（`curriculum.yaml` + 各 `.practice.md` + 题库），不在这个仓。
这里存一份副本就是第二份，加了课两边会漂。对账门：
`python3 ~/Edu/engine/app_pack.py <这个目录> --check`（已挂进 `~/Edu` 的 check_all）。

这个 README 进仓只为让目录存在。组装器每次都会清空目录再重建，
所以它由 `sync-lessons.sh` 在组装之后写回 —— 别手改，改了下次构建就没了。
