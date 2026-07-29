# Codex 额度

一个原生 macOS 菜单栏应用，通过本机 Codex 显示本周剩余额度。

应用使用 macOS 系统终端图标和原生 SwiftUI `MenuBarExtra`。菜单栏显示图标与剩余
百分比；点击会立即刷新并打开紧凑详情面板。“退出”是普通的小型一键按钮。

应用启动后默认每 30 秒自动刷新一次，适合在执行任务时紧密观察额度变化；也可在设置中
调整间隔。请求尚未结束时不会并发发起重复请求，用户切换账号或打开面板触发的刷新也不会
被丢弃。

## 数据来源

应用优先启动本机已有的官方 `codex app-server`，调用稳定的只读
`account/rateLimits/read` 方法。它使用 Codex 已有登录态，不读取、复制或显示令牌。
协议说明见 [OpenAI Codex app-server README](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)。
默认优先使用 `/Applications/ChatGPT.app/Contents/Resources/codex`，也会检查常见的
本地 Codex CLI 安装路径。如果检测到多个安装，可在设置中按安装来源、登录邮箱和套餐选择
要显示的账号；选定后不会在失败时静默切换到其他账号。

如果主动读取失败，应用会回退到 `~/.codex/sessions/**/*.jsonl` 里 Codex 自己写入的
`rate_limits` 快照。回退数据可能陈旧，界面会明确提示。周窗口按至少 6 天识别，
显示值为 `100 - usedPercent`。内部保留服务返回的小数精度，菜单栏和浮层最多显示两位
小数（末尾的零不显示），不会估算或编造。刷新失败或数据陈旧时，菜单栏会显示警告图标，
避免把旧百分比误认为实时结果。

## 构建

在项目目录执行：

```sh
./build-app.sh
```

生成 `outputs/Codex 额度.app`。构建脚本使用免费的本机临时签名（ad-hoc），不需要
Apple Developer 付费会员。

如需验证当前登录态下的真实只读额度链路：

```sh
CODEX_QUOTA_LIVE_TEST=1 swift test --filter readsLiveQuotaThroughSupportedAppServer
```

## 首次运行

1. 先确认 Codex 或 ChatGPT 已经登录；应用不会发起登录，也不会打开网页。
2. 双击 `outputs/Codex 额度.app`。如果 macOS 因本地构建来源拦截，前往
   “系统设置 → 隐私与安全性”，只对“Codex 额度”点击一次“仍要打开”。
3. 菜单栏出现代码图标和百分比。点击会立即重新读取并打开详情浮层。

macOS 仍可能在菜单栏空间不足时隐藏第三方项目；应用不使用位置强制、辅助功能控制或
未公开的菜单栏偏好。

无需额外文件权限、辅助功能权限或付费签名。应用未启用 App Sandbox，因为它需要
启动本机官方 Codex 子进程并读取 `~/.codex/sessions` 作为回退；它不会上传本地日志。

## 已知依赖

- 主数据接口是 OpenAI Codex app-server 的受支持接口。
- 本地日志字段 `payload.rate_limits` 是 Codex 当前写入的内部持久化形状，可能随版本
  变化，因此仅作为兼容回退。
- 若找不到可用 Codex 二进制、登录过期或网络不可用，应用保留最后一次有效值并显示错误；
  没有历史值时显示 `--%`。
