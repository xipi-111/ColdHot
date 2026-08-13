# ColdHot

ColdHot 是一个轻量的原生 macOS 菜单栏性能监控工具。点击菜单栏仪表图标即可查看实时指标，并可在设置中选择希望显示的内容。

- 官网：[xipiapp.com/coldhot](https://xipiapp.com/coldhot/)
- 最新官网版：[GitHub Releases](https://github.com/xipi-111/ColdHot/releases/latest)
- 系统要求：macOS 14 或更高版本

## 功能

- 7 个一级指标：CPU、GPU、内存、磁盘、网络、热状态和电池
- 点击指标卡片展开详情，同一时间只展开一张卡片
- CPU 分项、系统负载、每核心利用率、高 CPU 与高唤醒进程
- GPU Renderer/Tiler 利用率、显示器分辨率与刷新率
- 内存压力、构成、Swap 与高内存进程
- 磁盘容量、IOPS、累计吞吐与高读写进程
- 网络接口、数据包、累计流量及可选主动延迟测试
- 热状态、CPU/GPU/内存/NAND/电池/风道/Wi-Fi/PMU 按需温度
- 电池健康、循环次数、剩余时间、电气信息与 SMC 实时功率
- Dock 自动隐藏边缘触发零延迟快捷开关
- 1 秒、2 秒或 5 秒采样间隔
- 一级指标与详细项目独立选择并持久化

## 构建

项目提供两个独立的共享 Scheme：

- `ColdHot Direct`：官网/GitHub 分发版，保留完整传感器、进程排行和 Dock 快捷控制。
- `ColdHot App Store`：Mac App Store 版，启用 App Sandbox，并在编译期移除私有传感器、Dock 修改、跨进程排行以及依赖未文档化属性的 GPU/磁盘实时统计。

构建本机可安装的双版本测试包：

```sh
./Scripts/build-releases.sh local-test
```

测试包输出到 `dist/local-test`，使用临时签名，不能公开发布。生产包的证书、公证和 App Store 导出流程见 [DISTRIBUTION.md](DISTRIBUTION.md)。

最低系统版本为 macOS 14。应用使用 `LSUIElement`，因此只显示在菜单栏中，不显示 Dock 图标。

## 性能设计

采样器直接调用 Mach、libproc、IOKit、CoreGraphics、Network 和 SystemConfiguration，不会周期性启动 `top`、`ps` 或 `ioreg`。收起时只采集摘要；每核心、进程排行等详情只在对应卡片展开时采集。进程排行限制为约每 3 秒更新，磁盘容量限制为约每 30 秒更新。

官网版的电池卡片展开时会尝试通过只读 AppleSMC 键获取系统总功率、直流输入功率和电池功率。SMC 属于未公开接口，机型不支持时会自动回退到电池电压 × 电流的估算值；适配器额定功率不会被当作实时功耗。

官网版的温度项目默认关闭，只在“热状态”卡片展开且对应详细项已勾选时通过只读 SMC/HID 传感器采集。传感器键和值会按芯片代际过滤，缺失或明显异常的读数不会展示。App Store 版只显示系统公开的热压力等级。

网络延迟测试默认关闭；启用后会在网络卡片展开期间约每 10 秒连接一次 `1.1.1.1:443`。官网版的 Dock 弹出延迟使用 macOS 未公开的偏好键，因此未来系统版本可能不再支持，关闭快捷开关时会恢复修改前的值。

应用的隐私说明见 [PRIVACY.md](PRIVACY.md)，两个版本的设置窗口中也可以直接查看。
