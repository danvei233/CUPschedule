# 课堂录音后端与 Android 扩展

代码包含 Flutter 功能中心、Android 原生采集/Magisk 守护、Go API/任务系统及独立 Python 模型服务。
**GPU 模型未在开发机下载或运行。ColorOS 16 锁屏采集与 V100 推理须在目标设备验收，编译通过不代表设备验收通过。**

## Windows 开发与运行

Go 1.24+；SQLite 使用纯 Go 驱动，无需本机 C 编译器。启动配置在 `backend/config.toml`，运行数据目录由其中的 `data_dir` 指定。

```powershell
cd backend
go run ./cmd/server
# 或 go install github.com/air-verse/air@latest 后运行 air
# 部署构建
go build -o server.exe ./cmd/server
```

首次启动自动创建 `config.toml` 并生成随机 `api_key`；已有文件中密钥留空也会自动生成并保存，重启不会更换。直接打开文件复制密钥到 App，日志只打印文件位置。该文件已加入 Git 忽略。

```toml
api_key = "这里由服务器自动生成"
listen = "0.0.0.0:8090"
data_dir = 'D:\blackbook-data'
```

只生成配置、不启动服务：`go run ./cmd/server -init-config`。默认配置路径为工作目录中的 `config.toml`；可通过 `-config` 或 `BLACKBOOK_CONFIG` 指定。相对 `data_dir` 以配置文件所在目录为基准。修改后重启服务生效。
兼容 `BLACKBOOK_API_KEY`、`BLACKBOOK_LISTEN`、`BLACKBOOK_DATA_DIR` 环境变量，其非空值优先于文件；已有文件配置不会被环境覆盖写回。音频模型与 OpenAI 设置仍由 App 设置页面管理，保存在数据库。

默认只监听 `127.0.0.1:8090`，手机连接时按需改为局域网地址，并配置 Windows 防火墙。
App 填 `http://服务器IP:8090`，不要加 `/api/v1`。对外部署由反向代理终结 HTTPS/WSS。
所有 API、文件播放、WS 握手都要求 `X-API-Key`。没有公共静态音频目录，也不在 URL 放密钥。

数据布局：`课程安全目录名-短ID/YYYY-MM-DD-序号.wav`、`.chunks/录音UUID/`、`blackbook.db`。
`misc` 单独归档；课程改名保留历史目录；本地归档日期使用 Asia/Shanghai。
备份时停止 API，备份整个数据目录；不要仅复制运行中的 SQLite 主文件而遗漏 WAL。

## V100 Python 服务（仅在服务器执行）

建议 Python 3.10 x64。依赖基线是 CUDA 12 + cuDNN 8、CTranslate2 4.4、PyTorch 2.5.1 cu121。
不要自动升级到 CUDA 13 或去掉 Volta 支持的 PyTorch 构建。Windows 的 CUDA/cuDNN DLL 必须在 NSSM 服务进程的 PATH 内。

```powershell
cd backend/audio_service
py -3.10 -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install torch==2.5.1 torchaudio==2.5.1 --index-url https://download.pytorch.org/whl/cu121
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
$env:BLACKBOOK_AUDIO_KEY = '<与App服务端设置中的音频密钥一致>'
$env:HF_TOKEN = '<Hugging Face token>'
$env:BLACKBOOK_MODEL_DIR = 'D:\blackbook-models'
.\.venv\Scripts\python.exe -m uvicorn service:app --host 127.0.0.1 --port 8091 --workers 1
```

先在 Hugging Face 接受 `pyannote/segmentation-3.0` 和 `pyannote/embedding` 的模型访问条件。
服务默认不加载模型；在 App 设置中填入内部密钥，点击“加载”。仅显式加载时下载/初始化模型。
`BLACKBOOK_AUDIO_AUTOLOAD=1` 可在部署验收后开启自启动加载；`BLACKBOOK_WHISPER_MODEL` 可指定离线模型目录。
模型状态显示加载与推理错误，不使用假转写回退掩盖错误。

部署预检：

```powershell
.\.venv\Scripts\python.exe -c "import torch,ctranslate2; print(torch.cuda.get_device_name()); print(torch.cuda.get_device_capability()); print(ctranslate2.get_supported_compute_types('cuda'))"
```

Go 通过 HTTP 增量传送 PCM 封装的 WAV，并在最终校正时发送完整 WAV；不依赖共享路径。
Python 丢失会话时返回 `replay_required`，Go 从持久化音频重建会话。
diart 为每个录音保留聚类状态，Whisper 处理最近的滑动窗口；实时文本属于临时结果，最终校正替换它。
进程中的 GPU 模型访问串行化，避免 V100 显存竞争。Go 的 GPU 并发控制请求数量；建议保持 1。笔记并发独立，默认 2。
并发设大不保证线性加速；实际延迟、显存和中英文混合课堂识别质量在服务器测量。

## NSSM

`deploy/install-nssm.ps1` 注册两个独立 Windows 服务，不安装 Docker，不自动启动服务。
以管理员身份传入 API key、内部音频密钥、可选 HF token，注册后检查服务的 PATH、账户及模型目录权限。
再用 `nssm start BlackbookAudio`、`nssm start BlackbookApi` 启动。
App 的加载/卸载控制模型内存；NSSM 负责操作系统进程生命周期。

## Android 使用

1. 长按“关于”打开测试面板，启用“课堂录音与笔记扩展”，主页出现麦克风 FAB。
2. 功能中心设置后端地址、API key，点击连接同步。课程来源为已导入课表，`misc` 可手动录制。
3. 普通手动录音需要麦克风权限，前台服务显示通知。录音先写入私有目录，再分块校验上传。
4. 自动录音：Magisk 授权 → 安装守护 → 自检后立刻锁屏 → 等待后台采集 → 查看自检结果。
5. 只有自检成功才能开启全局自动录音；课程详情或“课程自定义提示词与录音开关”可排除课程。

Magisk 模块位于 `/data/adb/modules/blackbook_recorder`，独立 `app_process` 使用安装时 APK 的副本。
**更新录音器代码后重新运行 `flutter run`，点击“安装 / 更新并重启”即可，无需重启设备。**
按钮先结束录音、停止旧守护与其监护脚本，再原子替换 APK，启动新进程并核对本次启动标识与心跳。
旧版守护首次迁移可能等待约 40 秒；未能确认退出时不替换 APK。更新后重新执行锁屏麦克风自检。
“停止守护”同时禁用模块开机启动，保留录音及上传队列；再次安装 / 更新会启用它。
“查看日志”展示独立进程最近 120 行输出。
可在 Magisk 中禁用/移除模块。App 的扩展开关停止调度和当前录音，但保留已保存的待上传内容。
守护仅使用 App 私有文件作为 IPC，不开放本机 TCP 管理端口；PCM 和控制文件不设为全局可写。

自动调度需要 CPU 在锁屏时运行：当前守护在自动录音开启时续租部分唤醒锁，保持屏幕关闭，但增加待机耗电。
必须实测 ColorOS 的唤醒锁、音频身份和 SELinux 行为。自检失败会保留错误，**不会自动禁用 SELinux 或放宽系统策略**。
启动首次解锁后恢复调度；设备关机期间或采集进程崩溃造成的音频缺口不能恢复。
被中断的录音单独保存并标记，课时仍有效时创建新的恢复录音，不拼接成假连续音频。

同课、同日、相邻节次且间隔不超过设置阈值时合并，默认 30 分钟；起点提前 1 分钟。
冲突选择沿用课表，没有选择的冲突跳过。手动停止会抑制当前上课实例重新启动。
已有手动会话不被自动调度抢占。课程时间不从正在浏览的历史学期推断。

## 恢复、任务与配置语义

- 公共 WS 首帧 `resume` 返回已持久化分块清单。客户端发送 `{seq,sha256,data}`，data 为 PCM16 的 Base64。
- HTTP `POST /recordings/{id}/chunks` 使用同一结构；同序号同内容幂等，不同内容拒绝。
- 只有分块文件 fsync 并入库后返回 ACK。客户端在缺块时补传；`complete` 校验最终块数与内容。
- WS 使用 `?cursor=` 重放转写事件。`segment` 消息可能含 `replace_from`，先删除该时间点之后的旧片段，再应用后续片段。
- WS 断开不完成录音；上传完成只代表音频已保存，不要求笔记任务成功。
- 本地已上传文件保留 7 天；未上传文件不自动删除。空间不足停止采集并报告错误。
- 任务：queued/running/stopping/stopped/succeeded/failed/waiting_config。启动或重试从阶段边界恢复。
- 修改笔记会标记用户编辑；重新生成创建新版本。停止任务后已发送给第三方的请求可能仍产生上游费用，但取消结果不会写回。
- OpenAI 参数显式选择协议。空 reasoning 不发送参数；空密钥 PATCH 清空，省略密钥保持原值。
- 服务端配置保存在 SQLite。OpenAI 密钥不发回 App，日志不打印配置或请求认证头。
- 首次无配置录音可通过“连接、同步并重试上传”补上目标地址。已经绑定目标的录音不随服务器地址修改而迁移。

## 检查与验收

### App 离线录音与补传

- 音频先保存在设备的 PCM 分块中，服务器校验完成后合并成一份 WAV；没有网络也可以继续采集。
- 课程列表顶部的“本机录音与同步”显示所有本机记录。课程详情合并本机和服务器记录，离线时显示上次缓存的服务器列表。
- 每条录音显示上传进度、等待网络、等待配置、失败原因或“已上传并校验”，支持逐条重试和全部上传。分块达到 100% 仍需等待服务器完成校验。
- 守护或上传服务存活时自动重试；如果被系统终止，重新打开 App 或返回前台会恢复待上传队列。仅补传不申请麦克风权限。无 root 时不保证强行停止 App 后继续后台上传。
- 首次录音没有设置服务器时，配置连接后可补传。已有目标服务器的录音不会被自动发送到其他服务器；修改密钥后使用同一服务器的新密钥重试。
- 服务端确认前不自动清理本机音频，确认后保留 7 天。上传完成与转写、笔记完成分别显示。
- 更新原生录音代码后，需要安装新 APK，并在录音结束后更新、重启已安装的守护模块；热重载不会替换原生代码。

```powershell
cd backend
go test ./...
go vet ./...
cd ..
flutter analyze
flutter test
flutter build apk --debug
```

如果百度网盘等同步工具会向构建产物目录注入 `.baiduyun.uploading.cfg`，可以在 PowerShell 设置
`$env:BLACKBOOK_BUILD_DIR='E:/temp/blackbook-build'`，再在 `android` 目录执行
`./gradlew.bat :app:assembleDebug`。APK 在该目录的 `app/outputs/apk/debug/`，原始资源旁文件不会被删除。

无模型服务测试使用 `audio_service/test_service.py`，仅需 FastAPI、HTTPX 和 Uvicorn；模型模拟开关为 `BLACKBOOK_AUDIO_MOCK=1`。
真实模型验收：两名说话人的中文课堂样本、整节课连续录制、断网/断链/进程重启、后台自检、V100 显存及字幕延迟。
参考 [Android 后台麦克风限制](https://developer.android.com/develop/background-work/services/fgs/service-types)、[Magisk](https://topjohnwu.github.io/Magisk/guides.html)、[faster-whisper](https://github.com/SYSTRAN/faster-whisper)、[diart](https://github.com/juanmc2005/diart)。
