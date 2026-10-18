# delivery-localization 定点修复

任务：chapter-task:7b55688d99c14288a8debf6605bd6f82；复用 Chapter PID 19785 的声明，不释放。
范围：scripts/media/localization_shots.py、Tests/localization_receipt_test.py、本交接；不改其他工作树改动、暂存或后台，不推送、构建、装机、部署或发版。
完成条件：修复本仓截图回执契约，离线回归验证当前绑定可读取、输入变化失效，提交本地；固定 localization 及真实截图由 jobs 队列复验，不手写通过证据。

## 原失败与现场核对

原日志：/Users/tianli/Library/Application Support/app-sop/workbench/logs/748c12726a7740878fac9c09411d7068.log。
完整原件：perf/acceptance/run-og5rnxp8/localization.json，包含 dSYM、旧构建、handoff 快照与生成的 Watch/Info.plist 误报，以及缺中英截图和输入绑定。
project.yml 是三个 target 的 Info.plist 唯一源，均已声明 en、zh-Hans 与 en 开发语言；不修改忽略的生成 plist 或历史产物凑通过。
现场用 Chapter 当前 localization._apple(localization._files(root, skip_perf=True), root) 只读复核，选取 project.yml#WrongBook、#WrongBookWatch、#WrongBookWatchWidget，376 键、英文覆盖 1.0，issues=[]、missing=[]。共享扫描器已在其他执行中修正，本轮未修改 Chapter。

## 本轮修改与验证边界

截图脚本原来只有 screens 与 sim_lane 的 source_sha256，不满足固定验收器要求的 input_sha256 和 screenshots 语言索引。现在在 capture 前后读取 Chapter 的 business_code_files/digest_value 生产输入绑定；只有输入一致、八张图都在输出目录且 SHA 未变时才发布绑定和索引。仍保留原 sim_lane 包/源码验证、严格模拟器准入、75 延期与目视复核要求。
新增离线回归覆盖两语言索引、源码变化、图片篡改、路径越界，并用真实 PNG 和共享 _screenshots 验证当前输入可读取、改变输入失效。
命令：/Users/tianli/Dev/.venv/bin/python -m pytest -n auto Tests/localization_receipt_test.py Tests/localization_test.py -q。
结果：13 passed, 1 skipped（2.23 秒）；跳过项为未取得真实截图时的 OCR 检查，不计通过。git diff --check 通过。
真实截图未执行；现有 perf/acceptance/l10n/result.json 为构建槽繁忙导致 deferred/75，不得算截图通过。jobs 队列自动复验；无需用户决策，不扩大到其他 SOP 欠项。
