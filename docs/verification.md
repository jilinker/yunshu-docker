# 验证记录

日期：2026-10-11。首版镜像已在 OrbStack 构建并运行。最初验证时未登录云枢；同日用户登录后完成了下方追加的企业访问排查。

| 检查 | 状态 |
| --- | --- |
| Shell / Python 语法 | 已通过 |
| Compose 配置解析 | 已通过 |
| 镜像构建与 DEB 初始化 | 通过，云枢 2.3.10.47 / arm64，主要程序动态库无缺失 |
| 后台、GUI 与截图组件持续运行 | 通过，daemon、updater、screenshot_server 与 GUI 正常，健康检查通过 |
| 浏览器显示和操作 | 通过，VNC 连接正常，能显示云枢组织选择和登录界面 |
| SOCKS5 7171 实际转发 | 通过，受控域名 CONNECT 与 HTTP 往返、宿主机 HTTPS 请求均成功 |
| 容器停止、重启与状态保留 | 通过，停止约 5 秒，退出码 0；重启后服务和代理恢复 |
| 云枢登录后的企业目标入口访问 | 已通过，JumpServer 入口在容器直连、宿主机 SOCKS5 和当前 Clash TUN 环境下均返回 HTTP 200；认证流程未完成验证 |

已验证镜像 ID：`sha256:170ae0dd1dbd078e3c17bc5f26a4c8a852cc0832dbb58e49302fdd4d65f91cf5`。架构 `arm64`，Docker 报告镜像大小 `601957519` 字节。

实际代理验证：

- `python3 /usr/local/bin/verify-container.py`：真实 SOCKS5 握手、域名 CONNECT 和 HTTP 请求 / 响应通过，重启后再次通过。
- macOS `curl --noproxy '' --socks5-hostname 127.0.0.1:7171 --head https://example.com`：返回 `HTTP/2 200`，TLS 校验保持开启。
- 启动早期公网请求曾返回 SOCKS5 网络不可达；后续容器内请求与原始宿主机请求均通过，没有为此修改路由或 DNS。
- 当前 DNS 将 example.com 解析为 198.18 网段地址，沿用现有环境仍能转发；这不构成企业 DNS 或分流验证。

容器重建前后，`/etc/machine-id`、VNC 密码文件和客户端 `app_config.json` 的 SHA-256 均一致。未验证登录令牌或企业会话的持久化。

资源快照：未登录、GUI 与浏览器已连接时，CPU `2.14%`、内存 `241.9 MiB`，Docker PIDs `173`（包括线程）。这是一次快照，不是长期平均，也未与 aTrust 做性能对比。

本次处理的容器兼容问题：

- Ubuntu 初始 `/etc/machine-id` 为空，改为生成并从状态卷恢复。
- 截图组件需要 libjpeg-turbo 的 ABI，补入 Debian bookworm ARM64 兼容库。
- Chromium 沙箱 namespace 被 Docker 拒绝，采用厂商服务已有的 `--no-sandbox` 参数。
- 补齐 AT-SPI 会话服务和 Python 标准库。

浏览器截图保存在同目录的 `yunshu-gui.jpg`，仅作本地验证附件，不进入版本控制。

本项目未启动 `local-test`，也未修改 macOS 路由、Clash 或 OrbStack 全局设置。

## 登录后 JumpServer 访问排查

目标：`https://jumpserver.insta360.cn/`。容器为 `yunshu-docker-yunshu-1`，现有镜像和端口配置保持不变。

首次排查时，容器直连和容器内 SOCKS5 请求均返回 `HTTP/2 200`；企业域名解析为 `30.30.0.0`，路由经过 `tun0`。宿主机 `127.0.0.1:7171` 则立即拒绝 TCP 连接，尽管 Docker 显示了正确映射。

OrbStack 日志明确记录：

```text
failed to add forward: host: listen tcp4 127.0.0.1:7171: bind: address already in use
```

排查时未发现该端口仍被占用，短暂绑定并立即关闭也成功，说明此前冲突已解除；没有足够证据确定此前占用端口的进程。只重启 Dante、补充 IPv6 监听、临时调整 Dante 运行身份均未解决端口发布问题，两个临时配置改动均已撤销。

快速 `docker compose restart` 未刷新失效映射。分开执行 `docker compose stop yunshu` 和 `docker compose start yunshu`，确认 OrbStack 已先移除 3 个旧转发后，重新创建全部转发；macOS `lsof` 随后显示 OrbStack 正常监听 `127.0.0.1:7171`。

重启保留了已登录账号，但 GUI 显示“内网未连接”。点击“立即接入”后恢复“成功连网”，无需重新输入账号。接入前 Dante 曾请求解析到 `198.18.1.108` 的目标；接入后容器直连恢复 200，Dante 仍出现 TLS 超时。仅重启 Dante 后，容器内和宿主机 SOCKS5 请求均恢复 200，符合代理保留接入前域名解析状态的表现，尚未单独测量其缓存时长。

最终验证（TLS 证书校验保持开启）：

- 容器直连 JumpServer：`HTTP/2 200`。
- 容器内经 `127.0.0.1:7171` SOCKS5 访问：`HTTP/2 200`。
- macOS 经 `127.0.0.1:7171` SOCKS5 访问：`HTTP/2 200`。
- macOS 不显式指定代理、沿用当前 Clash TUN 环境访问：`HTTP/2 200`。
- 容器恢复 `healthy`，基础健康检查通过。

本次没有重建镜像，也没有新增常驻转发进程。恢复涉及原容器停止与启动、GUI 重新接入，以及仅重启 Dante。

验证边界：浏览器访问 JumpServer 会跳转到 `roles-test.insta360.cn`。按照用户最新要求，已停止该认证域名的验证。上述 HTTP 200 证明 JumpServer 入口可达，不代表认证页面和登录后的完整功能已经验证。
