# 参与忙僧

感谢你帮助完善忙僧。当前开发和测试目标是 Android，iOS 暂不推进。

## 报告问题

请在 Issue 中写明应用版本、手机型号、Android 版本、复现步骤、预期结果和实际结果。声音或动画问题可附录屏，并注明是否使用蓝牙耳机、是否开启系统减少动画或无障碍功能。

不要上传 API Key、个人数据文件或未经遮挡的隐私信息。

## 提交改动

1. Fork 仓库并克隆自己的 fork，将主仓库添加为 `upstream`。
2. 从最新主分支新建一个开发分支，一个 PR 尽量解决一个明确问题。
3. 修改并验证后，推送到自己的 fork，向 `BusyBlind-Team/BusyBlind` 的 `main` 提交 PR。
4. 在 PR 中说明问题、改动效果、验证方式及尚未验证的部分。关联对应 Issue；界面改动附截图，音频和动画改动尽量附真机录屏。
5. 等待维护者审核和合并。后续修复直接推送到同一分支，PR 会自动更新。

```bash
git remote add upstream https://github.com/BusyBlind-Team/BusyBlind.git
git fetch upstream
git switch -c fix/your-change upstream/main
# 修改代码
flutter analyze
flutter test
git add <改动文件>
git commit -m "fix: 描述具体问题"
git push -u origin fix/your-change
```

纯文档改动检查链接和说明即可。代码改动运行静态分析和测试；修复行为缺陷时补充能复现该问题的回归测试。音频、手势、后台恢复和动画问题还需要针对性的 Android 真机验证。

提交 PR 后检查 Actions 是否实际运行。没有检查结果不代表检查通过；若 fork 工作流需要维护者批准，在 PR 中说明即可。不要在不可信的 PR 工作流中使用发布密钥。

## 素材与授权

新增音乐、音效、图片或字体时，请同时写明来源、作者、许可证和所需署名。不要提交来源不明或不允许公开分发的素材。

贡献代码将按项目 MIT 许可证分发；第三方内容保留原有授权要求。
