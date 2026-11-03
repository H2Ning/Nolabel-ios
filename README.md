# Nolabel iOS（免费签名版）

这是只给自己用的 iOS 壳：启动时加载 `https://h2ning.com/Nolabel/`，登录 h2ning 账号后账单保存到账号，本机 `Application Support/Nolabel` 作为缓存和备份；用免费 Apple ID 侧载，不需要 Apple Developer Program，也不需要 Mac。

## 先确认网页源

网页源和 iOS 工程都在 `clock` 镜像里：

```text
C:\Users\34851\Desktop\clock\Nolabel
```

App 在线时直接加载 server 上的网页；`Nolabel/ios/NolabelApp/Resources/www` 是网络失败时使用的内置回退页面。以后改了回退网页，在 `Nolabel` 目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\ios\sync-web.ps1
```

也可以指定源目录：

```powershell
powershell -ExecutionPolicy Bypass -File .\ios\sync-web.ps1 -Source "C:\Users\34851\Desktop\clock\Nolabel"
```

## 目录

```text
clock/
  Nolabel/
    ios/
      project.yml                 XcodeGen 工程定义
      NolabelApp/
        Sources/
          NolabelApp.swift    SwiftUI 入口
          WebView.swift          WKWebView + JS bridge
          BillStore.swift        Application Support 下的账单文件
        Resources/
          Info.plist
          Assets.xcassets        App 图标、启动背景
          www/                   打包进去的网页
      ci/build-unsigned-ipa.sh   云端 macOS 构建脚本
      sync-web.ps1               同步网页文件
      .github/workflows/
        ios-unsigned-ipa.yml     GitHub Actions 构建
```

## 云端构建

不需要 Mac，用 GitHub Actions 的 macOS 机器构建：

1. 在 `clock/Nolabel/ios` 里新建一个独立的 GitHub 私有仓库，只推送这个 `ios` 目录；**不要推送整个 `clock`**，那里有 `.env`、`data.db`、`users.json` 等服务器数据。
2. 打开仓库的 **Actions → Build unsigned iOS IPA → Run workflow**。
3. 构建完成后下载 **Nolabel-unsigned-ipa** artifact，解压得到 `Nolabel-unsigned.ipa`。

这个 IPA 是未签名的，不能直接安装；下一步用 AltStore 或 Sideloadly 用你的免费 Apple ID 签名。构建过程不需要 Apple 账号。

## 安装（Windows）

### 方式一：Sideloadly

1. 在 Windows 安装 Apple Devices 或 iTunes（Sideloadly 依赖它识别 iPhone）。
2. 安装 Sideloadly，连接 iPhone，信任电脑。
3. 把 `Nolabel-unsigned.ipa` 拖进 Sideloadly，输入你的 Apple ID，开始。
4. iPhone 上按提示开启开发者模式、信任开发者。

Sideloadly 每次签名有效期 7 天，到期后重新连电脑签一次。

### 方式二：AltStore + AltServer

1. Windows 安装 AltServer 和 iTunes/iCloud，iPhone 安装 AltStore。
2. 手机和电脑在同一 Wi-Fi，AltStore 登录同一个 Apple ID。
3. 在 AltStore 的 My Apps 里用 “+” 选择 IPA 安装。
4. AltServer 保持运行时可从手机刷新，7 天一次。

AltStore 和 Sideloadly 都不需要越狱。

## 首次打开

- iOS 16 及以上：设置 → 隐私与安全性 → 开发者模式，打开并重启。
- 如果提示不受信任：设置 → 通用 → VPN 与设备管理 → 开发者 App → 信任。
- 7 天到期后 App 可能打不开，重新签名/刷新即可，数据一般还在。

## 数据

- h2ning 账号是主数据源。未登录不能保存和删除，登录后账单写入账号。
- 本机 `Application Support/Nolabel/bills.json` 是缓存，同时保留 `bills.backup.json` 和最近 30 份 `Snapshots/bills-*.json`。
- 启动时依次回退：主文件 → 备份 → 最新快照 → `Documents/Nolabel-backup.json`，避免单文件损坏直接丢账。
- 每次保存还会写一份 `Documents/Nolabel-backup.json`。Info.plist 已开启文件共享，可以在 iPhone 的“文件”App → 我的 iPhone → 诺诺 里找到，复制到 iCloud Drive 或电脑。
- 网页 localStorage 和原生 JSON 都只作缓存；退出登录会清空本机账单缓存，账号里的数据仍保留。
- Application Support 和 Documents 默认进入 iCloud/iTunes 备份；请保持系统备份开启。
- 免费签名刷新使用同一个 Bundle ID，正常刷新不会丢数据；删除 App 或重置手机才会丢本地文件，所以重要账目要额外导出。
- 导出的 JSON 是明文，放在网盘/电脑上时注意访问权限。

## 注意

- 当前是 **unsigned IPA**，只用于你自己的设备，不要公开分发。
- Bundle ID 是 `com.h2ning.nolabel`，最低 iOS 16.0；设备系统更低时告诉我调整。
- 不要用企业签、超级签；掉签和隐私风险不值得。
- Apple ID 密码不要交给第三方签名服务，也不要提交到仓库。
- 没有 GitHub 账号的话，可以用 Codemagic 建同样的 macOS 构建，但需要把仓库接过去。
