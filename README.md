# Nolabel iOS（纯 SwiftUI 原生版）

这是诺诺的 iOS 原生版本，使用 SwiftUI 构建，不再使用 WKWebView 或网页套壳。

- 最低 iOS 26，使用 Liquid Glass 材质，运行在 iOS 27 上使用系统最新玻璃效果。
- 账单页、记账页、3D 现钞舞台、键盘、计算器、设置、登录和导入导出全部是原生 SwiftUI。
- 账号优先：登录 h2ning 账号后账单保存到账号；本机 JSON 只作为缓存和备份。
- 未登录可以查看缓存，但不能保存或删除。
- 支持浅色、深色和跟随系统。

## 目录

```text
ios/
  project.yml                   XcodeGen 工程定义
  NolabelApp/
    Sources/
      NolabelApp.swift          App 入口和根视图
      Models.swift              账单、面额、金额和日期模型
      AccountAPI.swift          h2ning 账号和账号账单 API
      AppModel.swift            状态、登录、保存、月份和计算器
      BillsView.swift           账单页、日期胶囊和左滑删除
      DeleteConfirmView.swift   删除二次确认和当日免提示
      CashPlazaView.swift       总现钞现金广场和每日/累计混合图表
      EntryView.swift           记账页和键盘
      CashStageView.swift       原生 3D 现钞舞台
      SettingsView.swift        设置、登录、外观和日期弹层
      CSVDocument.swift         CSV 导入导出
      Theme.swift               颜色、字体和 Liquid Glass 辅助
      BillStore.swift           本地 JSON 缓存、备份和快照
    Resources/
      Info.plist
      Notes/                    纸钞图片资源
      Assets.xcassets           App 图标和启动背景
  ci/build-unsigned-ipa.sh      云端 macOS 未签名 IPA 构建
  .github/workflows/            GitHub Actions
```

## 账号和数据

- API 地址：`https://h2ning.com`
- 账号数据键：`app=nolabel`、`key=bills`
- 登录使用 h2ning 原生 JSON API，Cookie 由 URLSession 持久化。
- 网络请求会自动重试；冷启动断网时会在 2.5 秒后再试一次，设置页也提供手动“重试”。
- API 使用 `www.h2ning.com`；首次请求会等待 iOS 本地网络授权完成。如果 Wi-Fi/VPN/Tailscale 的 DNS 把域名解析到内网地址，设置页会直接显示该地址并提示关闭 VPN 或切换网络。
- 针对 iOS 27 对现有 TLC 证书链报 `-1202` 的情况，App 固定信任当前签发 `h2ning.com` 的 TLC DV TLS CA 中间证书作为兜底；系统信任正常时仍走系统校验，固定信任只用于该校验失败时，并且继续校验域名和有效期。
- `/api/user/get` 使用绝对 URL 构造，修复登录后读取账单时报 `-1002 不支持的URL` 的问题。
- 登录后账单写入账号，成功后写入本机 JSON 缓存。
- 首次登录会把本机旧缓存中不在账号里的账单合并到账号；退出登录会清空本机缓存，账号里的数据保留。
- 本机缓存位于 `Application Support/Nolabel/bills.json`，并保留备份和最近 30 份快照。
- `Documents/Nolabel-backup.json` 可在“文件”App 中复制到 iCloud Drive 或电脑。
- 免费签名刷新使用同一个 Bundle ID，正常刷新不会丢数据；删除 App 或重置手机才会丢本地缓存。

## 记账页

- 数字键盘支持小数、00、退格、长按退格清空、四则运算和等号。
- 金额实时拆分为 1–2–5 面额组合，并渲染为原生 SwiftUI 现钞舞台。
- 现钞舞台使用同一个 CATransformLayer 全局透视相机，不是每叠钞票各自透视；支持左右旋转和上下俯仰。
- 轻点舞台在整叠、按面额分组、全部展开三种视图间切换；大额按 1 万元成叠、10 万元成捆、100 万元装箱，并绘制捆扎带和封签。
- 点按该月支出汇总卡进入现金广场：上半部分按每笔账单的实际面额合计总现钞，下半部分为每日支出柱状图与累计支出折线图。
- 现金广场展示区和「记一笔」共用交互：无限水平旋转、俯仰、阻尼惯性；轻点切换整叠 / 分组 / 展开，展开网格可滚动。
- 删除账单前弹出二次确认，可勾选“今天之内不再提示”；当天后续删除直接执行，次日恢复确认。
- 触感使用统一语法：数字键轻点、运算符稍沉、等号补一拍、删除卡榫与落位、现钞模式一至三记拨盘、保存成功「数钞三连」；删除确认使用「烟花爆裂」——强中心爆破后接数记逐渐变轻的碎裂。设置中可切换「丰富 / 轻柔 / 关闭」，丰富力度已整体提高，旋转每约 15° 有一次明显拨轮卡榫。
- 现金广场和「记一笔」一样从底部滑入，关闭时向下滑出，背后账单同步变暗缩小。
- 现金广场关闭按钮在左上角、标题上方，内容整体下移。
- 设置是整页从右侧推出，左上角返回，可从屏幕左缘右滑返回；卡片宽度、边距和圆角与账单页一致。
- 备注、日期和时间可以修改；保存后回到账单页，取消保持原样。
- 记账页的现钞舞台完成首帧渲染后才显示金额卡和键盘，避免键盘先到、现钞后到。
- 账单左滑使用水平专用 UIKit 手势：从账单文字或金额上起手也能滑，纵向拖动不会被横向手势截走。

## 构建

不需要 Mac，使用 GitHub Actions 的 macOS 机器构建：

1. 把本目录推送到 GitHub 私有仓库。
2. 打开 **Actions → Build unsigned iOS IPA → Run workflow**。
3. 下载 **Nolabel-unsigned-ipa** artifact，解压得到 `Nolabel-unsigned.ipa`。
4. 在 Windows 用 Sideloadly 或 AltStore 使用免费 Apple ID 签名安装。

签名有效期 7 天，到期后重新签名。免费签名不能绕过 7 天限制。

## 截图和视觉检查

仓库另有 **Build and screenshot iOS app** workflow，默认手动运行，避免每次推送都等待约十分钟：

- 构建模拟器版本。
- 以预览数据启动并截取账单、记账、设置、登录、左滑删除等状态。
- 上传原始 `ios-screenshots` 和约 2MB 的 `ios-previews`（JPEG，最长边 1800px）。日常视觉检查只下载 `ios-previews`，需要原始 PNG 时再取完整 artifact。

预览参数只用于 CI 截图，不影响正式 App：

```text
--preview --preview-screen bills --preview-theme dark
--preview --preview-screen entry --preview-theme dark --preview-amount 52145
--preview --preview-screen settings --preview-theme dark --preview-user
```

## 注意

- 这是纯原生 SwiftUI App，不再需要把网页文件同步到 iOS 目录。
- Server 上的网页版本仍然独立存在；iOS App 只调用账号 API。
- 大额现钞舞台是 SwiftUI 原生近似实现，使用真实纸钞图片和 3D 变换，不包含网页版的全部包装箱细节。
- Bundle ID：`com.h2ning.nolabel`。
- 不要使用企业签、超级签或第三方签名服务；Apple ID 密码不要提交到仓库。
