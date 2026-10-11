# 云枢 Docker 镜像实施方案

日期：2026-10-11。首版镜像已构建并在 OrbStack 启动，后台、GUI、SOCKS5 转发和停止重启已通过验证。登录后 JumpServer 入口访问已返回 HTTP 200，浏览器认证流程未完成验证；详见 [验证记录](docs/verification.md)。下文保留实施阶段的技术依据和计划，当前使用方式以 [README](README.md) 为准。

## 1. 项目边界与交付目标

项目负责：在 Docker 镜像中正确安装云枢 DEB，启动其后台和图形客户端，并提供可用的 SOCKS5 代理端口。

| 项目内交付 | 项目外事项 |
| --- | --- |
| Ubuntu ARM64 基础镜像与运行依赖 | macOS 路由及系统代理设置 |
| DEB 安装初始化及云枢服务启动 | Clash / Mihomo 配置与规则分流 |
| 轻量 GUI，用于登录与操作云枢 | OrbStack 全局网络设置 |
| Dante SOCKS5，容器内部端口 **7171** | 企业 DNS 隔离、流量白名单及断线阻断 |
| 进程管理、日志和必要状态持久化 | 宿主机网络共存与分流验收 |
| Docker 启动示例与容器功能验证 | 额外网络策略和访问限制 |

宿主机绑定地址和端口由 Docker 启动参数或 Compose 配置决定，镜像不固定宿主机映射。默认采用普通 Docker bridge 网络，云枢自行建立所需访问路径，Dante 按容器当前路由转发。

代理不以 VPN 登录状态为启动门槛。VPN 未连接时，仍可能转发普通网络中可达的目标；企业目标能否访问取决于云枢连接状态和容器网络。项目不承诺所有代理流量必须经过 VPN。

已有的 `local-test` 保持关闭。当前已完成镜像和启动方案的首版落地。

## 2. 已有证据与可行性判断

### 2.1 用户实际验证的环境

用户提供的部署记录确认：Ubuntu 24.04 ARM64 安装指定依赖后，可以正常显示云枢 GUI，已验证命令为：

```text
/opt/apps/yunshu/files/yunshu-cross --disable-http2
```

历史显示方式为 XQuartz。Docker 方案将改用容器内虚拟桌面，因此 GUI 库和命令有已有依据，新的显示与会话环境仍待实测。

用户已在 OrbStack、Clash TUN 开启时正常使用 `hagb/docker-atrust`，其运行方式包含 `/dev/net/tun`、`NET_ADMIN`、Docker 端口发布及持久化目录。这为采用相同平台和同容器代理结构提供了依据，尚不能证明云枢后台与容器完全兼容。

### 2.2 云枢 DEB 静态检查

以下是落地前读取包内容得到的静态结果；后续构建已执行经适配的官方安装初始化，运行结果另见验证记录。

| 项目 | 检查结果 |
| --- | --- |
| 安装包 | `insta360_yunshu_2.3.10.47_arm64_insta360.deb` |
| Package / Version / Architecture | `yunshu` / `2.3.10.47` / `arm64` |
| SHA-256 | `2a1318ae2b4fa519645e864eb5aca608d158eff90b38b9040f02ea4f8e5a3025` |
| GUI | `/opt/apps/yunshu/files/yunshu-cross` |
| 后台 | `/opt/apps/yunshu/files/bin/yunshu-daemon` |
| 更新组件 | `/opt/apps/yunshu/files/bin/yunshu-updater` |
| 截图组件 | `/opt/apps/yunshu/files/bin/screenshot_server` |
| 隧道相关库 | 包含 `libtunnel.so`；运行机制待验证 |
| 其他模块 | 包含 `plugin/libeagleaudit.so`；安装脚本有对应初始化分支 |

关键发现：

- 包的 `control` 未声明 `Depends`，不能依靠包管理器自动补齐全部运行库。
- daemon 和 updater 的服务定义直接运行对应程序；daemon 未指定服务用户，按系统服务默认身份以 root 运行。
- 截图组件配置为用户服务，辅助脚本同时提供直接启动的回退路径。
- `postinst` 调用 `script/daemon.sh`，涉及服务、动态库、配置、自动启动与权限初始化；`chrome-sandbox` 设置为 4755。
- daemon、updater 和截图程序的直接启动现已通过未登录状态下的运行验证；使用 s6 与 tini 管理进程。登录后和客户端自更新的完整行为仍待验证。

当前判断：DEB 初始化、主要服务启动、GUI 显示和基础 SOCKS5 转发已可运行。剩余不确定性集中在登录后的服务要求、认证回调，以及 Dante 访问企业目标的结果。

### 2.3 参考来源

- 用户提供的《OrbStack Ubuntu 使用云枢（Yunshu）GUI 部署方案》：实际安装依赖与已验证启动方式，本地参考文档未包含在仓库中。
- [aTrust / EasyConnect 镜像组件](https://github.com/Hagb/docker-easyconnect/blob/master/Dockerfile)。
- [aTrust 的代理与图形服务启动](https://github.com/Hagb/docker-easyconnect/blob/master/docker-root/usr/local/bin/start.sh)。
- [Dante 配置模板](https://github.com/Hagb/docker-easyconnect/blob/master/docker-root/etc/danted.conf.sample)。

这些文档和源码用于确定实现方式，实际执行采用项目 Dockerfile 和启动脚本，并保留安装适配记录。

## 3. 与 aTrust 的复用关系

| 技术点 | aTrust 方案 | 云枢方案 |
| --- | --- | --- |
| 系统和架构 | Debian bookworm，兼容多个客户端 | Ubuntu 24.04 ARM64，匹配已成功环境和本地 DEB |
| 后台与代理 | 同一容器中的厂商后台和 Dante | 相同结构，后台改为云枢组件 |
| SOCKS5 | Dante，内部 1080 | Dante，内部 **7171** |
| 出口选择 | 多接口配置，`external.rotation: route` | 沿用按路由选择的思路，接口按云枢实际行为适配 |
| 图形服务 | TigerVNC + flwm，可启用 noVNC | TigerVNC + flwm，浏览器入口优先 easy-novnc |
| HTTP 代理 | 独立 Tinyproxy，8888 | 首版只交付 SOCKS5，减少常驻服务 |
| 浏览器认证交互 | aTrust 的 54631 等端口 | 仅在云枢实际需要时增加对应入口 |
| 客户端适配 | `utun7`、loginctl/getlogin 兼容及路由脚本 | 依据云枢错误与服务定义适配，不直接复制厂商补丁 |

复用重点是同容器运行和直接端口发布，省去 SSH 转发及额外代理层。aTrust 的 `route_localnet`、iptables 钩子和接口预创建都有特定背景，不作为云枢默认配置。

## 4. 镜像与组件选择

| 组件 | 规划 | 技术点 |
| --- | --- | --- |
| 基础镜像 | Ubuntu 24.04，`linux/arm64` | 与 DEB 架构一致，使用 Noble 的 `t64` 包名 |
| 云枢后台 | 按官方服务定义启动 | 保留程序所需身份、目录、动态库和初始化结果 |
| 云枢 GUI | 普通用户执行已验证命令 | 配置 HOME、DISPLAY 和必要用户会话环境 |
| 虚拟桌面 | TigerVNC + flwm | TigerVNC 提供虚拟 X 服务，先不叠加 Xvfb |
| 浏览器 GUI | 优先 easy-novnc | 一个服务提供网页和 VNC WebSocket 桥接，验证 ARM64 构建与兼容性 |
| 代理 | Dante | 容器内监听 `0.0.0.0:7171`，按现有路由转发 |
| 进程管理 | Ubuntu 的 s6 + tini | 负责 PID 1、信号、子进程回收和服务恢复，减少外部安装组件 |
| 会话支持 | 按实际需求提供 D-Bus 等组件 | 分别判断系统总线和用户会话总线，避免漏掉必要服务 |

基础运行参数先参考已成功的 aTrust：传入 `/dev/net/tun` 并授予 `NET_ADMIN`。其他设备和权限按云枢运行需要补齐，不将权限精简作为首版阻塞条件，也不在缺少证据时直接预设完整特权。

默认保留 DEB 中的完整客户端组件。能否省去 updater、截图或其他模块，在客户端正常运行后判断。若后台确实需要 systemd 的真实服务语义，再评估相应容器启动方式，不能把服务定义中的简单 ExecStart 当成已验证结论。

## 5. 依赖安装与 DEB 初始化

### 5.1 已成功依赖基线

第一版使用用户实际安装过的依赖：

```text
x11-apps libglib2.0-bin libnss3 libnspr4
libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 libgtk-3-0t64
libpango-1.0-0 libcairo2 libxcomposite1 libxdamage1 libxrandr2
libgbm1 libdrm2 libxkbcommon0 libasound2t64 libatspi2.0-0t64
```

另加入 Dante、TigerVNC、flwm、中文字体、证书、D-Bus、AT-SPI 和必要诊断工具。easy-novnc 固定 v1.1.0 的提交，s6 与 tini 使用 Ubuntu 软件包。截图程序实测需要带 `LIBJPEGTURBO_6.2` 符号的兼容库，已补入 Debian bookworm ARM64 的 libjpeg-turbo。

库主要影响镜像体积，不等于增加常驻内存。首版先复现完整依赖，之后再清理仅用于诊断的工具。

### 5.2 安装流程适配

实施顺序：

1. 校验 DEB 的架构、版本和 SHA-256，安装依赖。
2. 梳理 `postinst` 与 `daemon.sh` 的安装副作用，区分文件初始化、系统集成及启动服务。
3. 在镜像构建中完成必要的文件、动态库、权限与配置初始化；长驻程序在容器运行阶段启动。
4. 明确处理构建阶段不能执行的服务控制操作，保留可诊断的安装结果。
5. 检查 GUI、后台和插件的依赖，再通过实际启动补充动态加载库。

优先保留官方安装行为；需要适配时，逐项记录原操作、适配原因及替代方式。`policy-rc.d` 无法拦截全部直接 `systemctl` 调用，不能用无条件成功的替身把未完成的初始化隐藏起来。

保留安装脚本设置的 `chrome-sandbox` 权限。实测 Docker 默认权限会阻止 Chromium 创建沙箱 namespace，因此 GUI 采用厂商服务已有的 `--disable-http2 --no-sandbox` 命令；Chromium 自身沙箱在首版中关闭。

## 6. 启动与生命周期

预期启动关系：

```text
容器 PID 1 / 进程管理
├─ 云枢后台及所需系统服务
├─ TigerVNC → flwm → 用户会话与云枢 GUI
├─ 必要用户组件，例如截图服务
├─ easy-novnc → TigerVNC
└─ Dante → 容器当前网络 → 目标服务
```

运行阶段：

1. 准备运行目录、用户 HOME、状态目录及权限。
2. 启动必要系统服务和云枢后台。
3. 启动虚拟桌面、窗口管理器和必要用户会话。
4. 启动 GUI，使用 `/opt/apps/yunshu/files/yunshu-cross --disable-http2 --no-sandbox`。
5. 启动浏览器入口和 Dante。Dante 的启动时机由实际接口要求决定，不以用户完成登录为条件。
6. 用户通过 GUI 登录云枢，验证代理能访问云枢网络中的目标。

后台和用户组件的最终顺序按实际依赖调整。使用进程、socket 或端口就绪条件，不依赖固定的长时间等待。

| 场景 | 预期行为 |
| --- | --- |
| 尚未登录 | GUI 可操作，代理服务可启动，容器持续运行 |
| 云枢连接后 | Dante 使用容器现有访问路径转发 |
| VPN 断开 | 客户端可重新连接；代理按当前网络继续工作 |
| GUI 或后台意外退出 | 对需要恢复的服务设置重试间隔，保留错误日志 |
| Docker 停止 | 转发终止信号，给客户端保存状态与正常退出的时间 |
| 关闭浏览器标签 | 容器中的桌面和云枢继续运行 |

健康检查只检查应常驻的基础服务和代理监听情况。等待登录不应触发重启循环；代理监听正常也不能证明企业目标可访问。Docker 标记 `unhealthy` 本身不会触发 Compose 重启。

## 7. 代理端口与转发实现

### 7.1 固定镜像内接口，启动时决定发布方式

| 服务 | 容器内端口规划 | 说明 |
| --- | --- | --- |
| SOCKS5 | **7171/TCP** | 镜像的核心代理出口 |
| 浏览器 GUI | 6080/TCP | 规划默认值，可由组件配置调整 |
| 原始 VNC | 5901/TCP | 按需在启动时发布 |

`EXPOSE` 仅声明端口，不会创建宿主机映射。后续启动文档提供 `-p <宿主机地址>:<宿主机端口>:7171` 或等价 Compose 配置；本项目不规定宿主机的唯一绑定地址或端口。

### 7.2 Dante 配置思路

- 默认提供与 aTrust 类似的开放转发规则，不增加目标域名、网段白名单或 VPN 状态拦截。
- 沿用 `external.rotation: route` 的思路，让容器网络和云枢决定目标访问路径。
- 识别真实出口接口，不硬编码 aTrust 的 `utun7`，也不假设云枢一定使用 `tun0`。
- aTrust 在启动时生成接口列表并临时创建 VPN 接口；云枢是否需要类似处理，在运行中确认。
- 若 Dante 不能识别后创建的接口，验证在连接后重新加载配置或重启 Dante 的方式。
- 域名交由容器已有解析环境处理，不增加独立 DNS 服务；验证 SOCKS5 域名请求是否能正常解析实际目标。
- 首版核心验收为 SOCKS5 TCP CONNECT。UDP 转发涉及额外数据端口与发布方式，不能仅凭映射 7171/TCP 宣称支持。

如果云枢只提供特定进程的访问能力，需要确认 Dante 是否能够复用，并针对客户端做适配。代理正常转发、登录后仍能通过 Docker 发布端口访问，均属于容器功能问题；只有实际失败时才定位必要的容器内兼容处理，不预先设计策略路由系统。

## 8. 持久化、日志与资源占用

GUI 使用独立用户 HOME。`~/.config/YunshuCross` 是从安装脚本识别出的候选状态目录；后台的 `files/config`、`logs`、`tmp`、`db` 是否需要持久化，登录后按实际写入确认。

挂载范围以必要状态为准，避免覆盖整个程序安装目录。运行目录和临时 socket 保留在容器文件系统中；命名卷或绑定目录由启动示例说明。

基础服务日志输出到 Docker 日志，云枢自有日志保留明确路径；对持续写入日志设置轮转。安装包、登录状态和日志采用本地存储，示例不包含真实登录凭据。

资源优化首先来自组件数量：轻量窗口管理器、同容器 Dante、单服务浏览器入口，省去完整桌面、SSH 转发、独立 HTTP 代理及额外 Xvfb。功能通过后观察空闲状态和代理使用时的 CPU、内存与进程数量，再处理实际占用较高的组件，不预先承诺性能数值。

## 9. 实施阶段与验收

| 阶段 | 工作内容 | 通过条件 | 状态 |
| --- | --- | --- | --- |
| S0 静态梳理 | DEB、服务定义、安装脚本和参考依赖 | 明确主要组件与适配点 | 已完成静态检查 |
| S1 镜像安装 | Ubuntu ARM64、依赖、DEB 初始化 | 构建完成，程序、库、权限及配置完整 | 已通过构建和主要程序检查 |
| S2 正常启动 | 后台、会话、虚拟桌面和 GUI | 云枢可操作、必要服务持续运行、能够完成登录 | 启动和 GUI 已通过；账号登录待用户完成 |
| S3 代理接入 | Dante 7171 与启动时端口发布 | 实际 SOCKS5 请求成功，连接云枢后能访问目标服务 | 基础转发已通过；企业目标待登录后验证 |
| S4 工程完善 | Compose、持久化、日志和进程恢复 | 停止、启动、容器重建及使用说明可复现 | 基础停止、重启及配置保留已通过 |

验收证据包括：

- 镜像架构、云枢版本、构建结果及关键安装步骤。
- 浏览器可显示和操作 GUI，后台没有缺库或反复退出。
- 必要服务运行，关闭浏览器后客户端仍持续运行。
- Dante 监听容器内 7171，实际 TCP CONNECT 和域名请求成功。
- 登录后通过代理访问指定云枢目标，而非只检查端口开放。
- 登录后图形与代理入口仍可用，服务故障日志可定位。
- 容器重建后配置按所选持久化方式保留；会话失效时可重新登录。

基础验收不依赖 Clash，不测试宿主机分流、DNS 隔离或断线阻断。代理端口转发测试只使用部署时选定的发布方式。

## 10. 预期项目文件

下列主要文件已经创建。s6 的各服务目录由 Dockerfile 生成到镜像中的 `/etc/yunshu/services`。

```text
yunshu-docker/
├── IMPLEMENTATION_PLAN.md
├── Dockerfile
├── compose.yaml
├── .dockerignore
├── .gitignore
├── .env.example
├── README.md
├── config/
│   ├── danted.conf
│   └── danted.rules
├── scripts/
│   ├── install-yunshu.sh
│   ├── entrypoint.sh
│   ├── run-service.sh
│   ├── start-dante.sh
│   ├── stop-services.sh
│   ├── defer-build-services.py
│   ├── verify-container.py
│   └── healthcheck.sh
└── docs/
    └── verification.md
```

`install-yunshu.sh` 记录包初始化的适配；`run-service.sh` 管理厂商程序及其他组件的启动环境；s6 负责长驻服务恢复，`start-dante.sh` 只负责接口变化后的配置更新。

安装包通过被版本控制排除的 `installers/yunshu.deb` 提供给构建。`.env.example` 用于端口映射、桌面分辨率等启动配置，不存真实账号密码。

## 11. 待实测技术点

1. 登录后或更新时，daemon 与 updater 是否要求更多系统服务、设备或权限；当前直接启动和系统 D-Bus 运行已通过初始验证。
2. 安装脚本涉及的后台、截图和其他模块，哪些是正常登录和访问所必需。
3. 登录后的 GUI 会话和截图功能；当前 TigerVNC、用户会话、中文显示和使用 `--no-sandbox` 的 GUI 启动已通过验证。
4. 云枢是否需要浏览器认证、回调端口或其他桌面组件。
5. 云枢的实际访问机制，以及 Dante 的出口选择和接口更新方式。
6. GUI 与后台的状态写入位置、容器重建后保留情况，以及 updater 对版本和文件的影响。

后续验证从当前可运行的镜像继续，完成云枢账号登录及企业目标访问检查。
