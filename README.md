# QuotaDeck

macOS 菜单栏应用:集中查看所有 AI Coding Plan 的 **5 小时余量 / 周余量 / 余额**,像 QuotaBar 一样以卡片+进度条展示。

- 菜单栏常驻显示当前最紧张的额度(如 `GLM / Z.ai 5h 98%`)
- 管理窗口四页:**总览**(卡片)/ **集成**(配置各家 key)/ **统计**(刷新历史)/ **诊断**(原始响应)
- 纯 Swift(SPM + SwiftUI + libsqlite3),零第三方依赖,约 10MB

## 快速开始

```bash
# 方式一:直接跑
swift run QuotaDeck

# 方式二:打包成 .app(无 Dock 图标,仅菜单栏)
./scripts/make-app.sh
open build/QuotaDeck.app

# CLI:终端查看 / 调试数据层
swift run QuotaDeckCLI            # 表格输出
swift run QuotaDeckCLI --json     # JSON 输出
swift run QuotaDeckCLI --raw      # 附带各接口原始响应
```

配置文件:`~/Library/Application Support/QuotaDeck/config.json`(权限 0600,含 key)。

## 各家接入方式

| 家 | 数据来源 | 需要什么 |
|---|---|---|
| **GLM / Z.ai** | ① API:`GET https://open.bigmodel.cn/api/monitor/usage/quota/limit`(协议与 ZCode 官方一致,返回 `data.limits[]`,含 TIME_LIMIT 五小时窗口与周窗口的 usage/remaining/percentage/nextResetTime;团队版加 `?type=2`)② 无 key 回退:读 `~/.zcode/cli/db/db.sqlite` 的 `turn_usage` 表本地估算 5 小时窗口 | BigModel Coding Plan 的 API Key([bigmodel.cn 控制台](https://bigmodel.cn));不填也能本地估算 |
| **中转站** | new-api/one-api 兼容计费接口:`/v1/dashboard/billing/subscription` + `/usage` | 站点地址 + sk- key;首次运行会自动从 `~/.claude/settings.json` 导入 Claude Code 正在用的中转 |
| **Kimi** | 官方 `GET https://api.kimi.com/coding/v1/usages` | Kimi Code 控制台的 `sk-kimi-` key |
| **Grok** | xAI 管理 API `GET https://api.x.ai/v1/api-key`(余额/credits) | xAI key([console.x.ai](https://console.x.ai)) |
| **Codex** | 非官方 `GET https://chatgpt.com/backend-api/rate_limits` | ChatGPT 订阅模式的本机 `~/.codex` 凭据,或手动填访问令牌;API key/中转模式下显示"未配置" |

## 设计说明

- **Provider 插件式架构**(`Sources/QuotaDeckCore/`):每家一个 `QuotaProvider` 实现,互不影响,加一家只需新增一个 struct 并注册。
- **GLM 无公开文档**:配额接口协议是从本机 ZCode 3.14.5 的 host 源码(`app.asar`)逆向得到的,字段解析做了宽松处理,结构变化时看"诊断"页原始响应即可校准。
- **本地估算算法**:按锚定窗口(窗口从窗口内第一条记录起算,跨度 5 小时,越过关闭时刻则重新开窗)统计 prompt 数,上限可在集成页配置(默认 120)。
- **直连网络**:内置 URLSession 禁用代理(系统代理常指向未运行的本地端口),目标接口均为直连可达。

## 已知限制

- GLM `percentage` 字段按"已用百分比"解析,如与实际相反,以诊断页原始响应校准;
- MCP 额度接口(`zcode.z.ai/api/v1/mcp/usage`)依赖 ZCode 在线凭据,独立调用大概率 401(默认关闭);
- Antigravity(需监听本地端口)与 Claude Code 本地用量统计为二期方向。

## 致谢

配额监控思路参考社区项目 [QuotaBar](https://github.com/chilohwei/QuotaBar)、[CodexBar](https://github.com/steipete/CodexBar)、[cc-bar](https://github.com/nanvon/cc-bar);GLM 接口协议逆向自 ZCode 官方客户端。
