#Requires -Version 5.1
<#
  publish.ps1 —— 把演示原型与需求文档发布到 GitHub Pages
  （双击 发布更新.bat 时自动调用本脚本）

  用法（在本文件所在目录）：
    .\publish.ps1                                   # 发布当前工作区最新版
    .\publish.ps1 -Note "检查类型扩展为四类"           # 带更新说明
    .\publish.ps1 -Source ..\其他演示.html            # 指定其他源文件
    .\publish.ps1 -RenderOnly                        # 只重建首页，不发布
    .\publish.ps1 -NoPush                            # 提交但不推送
    .\publish.ps1 -Prompt                            # 交互式询问更新说明（bat 用）

  行为：把源 HTML 快照归档到 versions\<日期>-v<版本>\index.html，
        同时覆盖 latest.html，并重建首页 index.html。
#>
[CmdletBinding()]
param(
    [string]$Source,
    [string]$Docx,
    [string]$Note = '',
    [switch]$RenderOnly,
    [switch]$NoPush,
    [switch]$Prompt
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

# 双击 bat 时带 -Prompt：中文提示放在这里而不敢放进 .bat，
# 因为 cmd.exe 用 OEM 代码页(936)解析 bat，UTF-8 中文会被拆成乱码路径。
if ($Prompt -and -not $Note -and -not $RenderOnly) {
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  发布演示站到 GitHub Pages" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    $Note = Read-Host "请输入本次更新说明（可留空直接回车）"
    Write-Host ""
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}
function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}
function ConvertTo-JsonString([string]$Value) {
    if ($null -eq $Value) { return '""' }
    $s = $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '').Replace("`n", '\n')
    return '"' + $s + '"'
}

# ---------------------------------------------------------------- 1. 归档源文件
$verName = ''
if (-not $RenderOnly) {
    $workspace = Split-Path $root -Parent
    if (-not $Source) { $Source = Join-Path $workspace '0917优化项.html' }
    if (-not (Test-Path $Source)) { throw "找不到源文件：$Source" }
    $Source = (Resolve-Path $Source).Path
    $srcDir = Split-Path $Source -Parent

    if (-not $Docx) {
        $cand = Get-ChildItem $srcDir -Filter '安全质量管理模块需求说明书_V*.docx' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '备份' } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($cand) { $Docx = $cand.FullName }
    }

    $html = Read-Utf8 $Source
    $m = [regex]::Match($html, 'data-prd-version="([^"]+)"')
    $prdVer = if ($m.Success) { $m.Groups[1].Value } else { '0' }
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $verName = "$today-v$prdVer"
    $verDir = Join-Path $root "versions\$verName"

    # 提示一：同一天同一版本号会覆盖已有快照，历史列表不会新增一行
    if (Test-Path $verDir) {
        Write-Host "提示：versions\$verName 已存在，本次将覆盖该日期的快照，历史列表不会新增一行。" -ForegroundColor Yellow
        Write-Host "      若要把这次更新单独留存，请先把 HTML 里的 data-prd-version 改成新值（例如 1.6 → 1.7）。" -ForegroundColor DarkGray
    }

    # 提示二：需求文档版本与 HTML 内嵌版本不一致，会导致归档文件名与内容对不上
    if ($Docx -and (Test-Path $Docx)) {
        $dv = [regex]::Match((Split-Path $Docx -Leaf), '_V([\d.]+)_').Groups[1].Value
        if ($dv -and $dv -ne $prdVer) {
            Write-Host "提示：需求文档是 V$dv，而 HTML 内嵌版本是 V$prdVer，两者不一致。" -ForegroundColor Yellow
            Write-Host "      文档会按 V$prdVer 命名归档，建议先把两处版本号统一。" -ForegroundColor DarkGray
        }
    }

    New-Item -ItemType Directory -Force -Path $verDir | Out-Null
    Copy-Item $Source (Join-Path $verDir 'index.html') -Force
    Copy-Item $Source (Join-Path $root 'latest.html') -Force

    $docxFile = ''
    if ($Docx -and (Test-Path $Docx)) {
        $docxFile = "需求说明书-V$prdVer.docx"
        Copy-Item $Docx (Join-Path $verDir $docxFile) -Force
    }

    # 另存一份可下载的单文件演示（浏览器打开 index.html 会直接显示，
    # 想「下载」需要一个带扩展名的独立文件名 + 链接上的 download 属性）
    $htmlFile = "安全质量演示-V$prdVer.html"
    Copy-Item $Source (Join-Path $verDir $htmlFile) -Force

    $meta = '{' + "`n" +
            '  "version": ' + (ConvertTo-JsonString $prdVer) + ',' + "`n" +
            '  "date": ' + (ConvertTo-JsonString $today) + ',' + "`n" +
            '  "note": ' + (ConvertTo-JsonString $Note) + ',' + "`n" +
            '  "source": ' + (ConvertTo-JsonString (Split-Path $Source -Leaf)) + ',' + "`n" +
            '  "htmlFile": ' + (ConvertTo-JsonString $htmlFile) + ',' + "`n" +
            '  "docx": ' + (ConvertTo-JsonString $docxFile) + "`n" +
            '}' + "`n"
    Write-Utf8NoBom (Join-Path $verDir 'meta.json') $meta
    Write-Host "已归档版本：$verName" -ForegroundColor Green
}

# ---------------------------------------------------------------- 2. 重建首页
$versionsRoot = Join-Path $root 'versions'
$items = @()
if (Test-Path $versionsRoot) {
    foreach ($dir in (Get-ChildItem $versionsRoot -Directory | Sort-Object Name -Descending)) {
        $metaPath = Join-Path $dir.FullName 'meta.json'
        # 注意：PowerShell 变量名不区分大小写，这里的局部变量绝不能叫 $note/$docx/$ver/$date，
        # 否则会覆盖同名参数（$Note/$Docx），导致提交信息用错、参数失效。
        $mv = $dir.Name; $md = $dir.Name; $mn = ''; $mx = ''; $mh = ''
        if (Test-Path $metaPath) {
            try {
                $obj = (Read-Utf8 $metaPath) | ConvertFrom-Json
                if ($obj.version) { $mv = $obj.version }
                if ($obj.date) { $md = $obj.date }
                if ($obj.note) { $mn = $obj.note }
                if ($obj.docx) { $mx = $obj.docx }
                if ($obj.htmlFile) { $mh = $obj.htmlFile }
            } catch { Write-Warning "meta.json 解析失败：$metaPath" }
        }
        # 旧版本快照没有 htmlFile 字段，回退到目录里那个可下载的 html
        if (-not $mh) {
            $fallback = Get-ChildItem $dir.FullName -Filter '*.html' -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -ne 'index.html' } | Select-Object -First 1
            $mh = if ($fallback) { $fallback.Name } else { 'index.html' }
        }
        $items += [pscustomobject]@{ Dir = $dir.Name; Ver = $mv; Date = $md; Note = $mn; Docx = $mx; Html = $mh }
    }
}

$latest = if ($items.Count -gt 0) { $items[0] } else { $null }
$rows = ''
foreach ($it in $items) {
    $link = "versions/$($it.Dir)/index.html"
    $htmlLink = "versions/$($it.Dir)/$($it.Html)"
    $docxCell = if ($it.Docx) { '<a class="dl" href="versions/' + $it.Dir + '/' + $it.Docx + '">下载</a>' } else { '<span class="muted">—</span>' }
    $noteCell = if ($it.Note) { [System.Net.WebUtility]::HtmlEncode($it.Note) } else { '<span class="muted">—</span>' }
    $rows += '<tr><td class="ver">V' + $it.Ver + '</td><td>' + $it.Date + '</td><td>' + $noteCell + '</td>' +
             '<td class="nowrap"><a class="open" href="' + $link + '">打开</a><span class="sep"></span>' +
             '<a class="dl" href="' + $htmlLink + '" download>下载HTML</a></td><td>' + $docxCell + '</td></tr>' + "`n"
}
if (-not $rows) { $rows = '<tr><td colspan="5" class="muted" style="text-align:center;padding:28px">暂无版本</td></tr>' }

$latestVer = if ($latest) { 'V' + $latest.Ver } else { '—' }
$latestDate = if ($latest) { $latest.Date } else { '—' }
$latestNote = if ($latest -and $latest.Note) { [System.Net.WebUtility]::HtmlEncode($latest.Note) } else { '暂无更新说明' }
$latestHtml = if ($latest) {
    '<a class="btn ghost" href="versions/' + $latest.Dir + '/' + $latest.Html + '" download>下载演示文件（HTML）</a>'
} else { '' }
$latestDocx = if ($latest -and $latest.Docx) {
    '<a class="btn ghost" href="versions/' + $latest.Dir + '/' + $latest.Docx + '">下载需求说明书 ' + $latestVer + '</a>'
} else { '' }
$updatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm')

$tpl = @'
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>安全质量模块 · 研发演示站</title>
<style>
*{box-sizing:border-box}
body{margin:0;font:14px/1.7 "Microsoft YaHei",system-ui,sans-serif;color:#26364d;background:#f4f7fb}
.wrap{max-width:940px;margin:0 auto;padding:32px 20px 60px}
h1{font-size:24px;margin:0 0 6px;color:#162a44}
.sub{color:#6b7c92;margin:0 0 26px}
.card{background:#fff;border:1px solid #dce7f7;border-radius:8px;padding:22px 24px;box-shadow:0 6px 20px rgba(23,91,221,.06)}
.card h2{margin:0 0 4px;font-size:19px;color:#175bdd}
.meta{color:#6b7c92;font-size:13px;margin-bottom:14px}
.note{margin:0 0 18px;padding:10px 12px;background:#f7faff;border:1px solid #e2ebf7;border-radius:4px;color:#45648f}
.actions{display:flex;flex-wrap:wrap;gap:10px}
.btn{display:inline-block;padding:10px 18px;border-radius:4px;background:#175bdd;color:#fff;text-decoration:none;font-weight:500}
.btn:hover{background:#1450c4}
.btn.ghost{background:#fff;color:#175bdd;border:1px solid #b9cff5}
.btn.ghost:hover{background:#f2f7ff}
h3{font-size:16px;margin:34px 0 12px;color:#162a44}
table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #e2e9f3;border-radius:6px;overflow:hidden}
th,td{padding:11px 12px;border-bottom:1px solid #eef2f8;text-align:left;font-size:13px;vertical-align:top}
th{background:#eef3fa;color:#263e61;font-weight:600;white-space:nowrap}
tr:last-child td{border-bottom:0}
td.ver{font-weight:600;color:#175bdd;white-space:nowrap}
td.nowrap{white-space:nowrap}
span.sep{display:inline-block;width:1px;height:12px;margin:0 8px;background:#dbe3ee;vertical-align:-1px}
a.open{color:#175bdd;text-decoration:none;white-space:nowrap}
a.open:hover{text-decoration:underline}
a.dl{color:#1677a8;text-decoration:none;white-space:nowrap}
a.dl:hover{text-decoration:underline}
.muted{color:#9aa6b6}
.tips{margin-top:26px;padding:16px 18px;background:#fff;border:1px solid #e2e9f3;border-radius:6px;color:#4e5969;font-size:13px}
.tips b{color:#175bdd}
code{background:#f2f4f7;padding:1px 5px;border-radius:3px;font-family:Consolas,monospace}
footer{margin-top:30px;color:#86909c;font-size:12px;text-align:center}
</style>
</head>
<body>
<div class="wrap">
  <h1>安全质量管理模块 · 研发演示站</h1>
  <p class="sub">本地址固定不变，每次发布只更新内容，请直接收藏本页。</p>

  <div class="card">
    <h2>最新版本 {{LATESTVER}}</h2>
    <div class="meta">发布日期：{{LATESTDATE}} ｜ 站点更新时间：{{UPDATED}}</div>
    <p class="note">{{LATESTNOTE}}</p>
    <div class="actions">
      <a class="btn" href="latest.html">打开演示</a>
      {{LATESTHTML}}
      <a class="btn ghost" href="versions/{{LATESTDIR}}/index.html">固定版本快照</a>
      {{LATESTDOCX}}
    </div>
  </div>

  <h3>历史版本</h3>
  <table>
    <thead><tr><th>版本</th><th>日期</th><th>更新说明</th><th>演示</th><th>需求文档</th></tr></thead>
    <tbody>
{{ROWS}}    </tbody>
  </table>

  <div class="tips">
    <p><b>地址说明</b>：<code>latest.html</code> 始终指向最新版，可长期作为研发的固定入口；<code>versions/</code> 下是按日期归档的历史快照，用于回溯"当时那一版长什么样"。</p>
    <p><b>下载演示文件</b>：演示是<b>完全自包含的单文件 HTML</b>（无外部 JS/CSS/图片依赖）。点「下载演示文件（HTML）」保存到本地后，双击即可离线打开，也可以直接转发给别人；历史版本里每一版都能单独下载。</p>
    <p><b>需求文档</b>：与演示同版本的 Word 文档随版本一起归档，点右侧"下载"获取。</p>
    <p><b>如何更新</b>：在本地 <code>demo-site</code> 目录双击 <code>发布更新.bat</code>，填写更新说明即可。地址不变，无需再逐个发文件。</p>
  </div>

  <footer>安全质量管理模块 · 演示原型与需求说明</footer>
</div>
</body>
</html>
'@

$latestDir = if ($latest) { $latest.Dir } else { '' }
$out = $tpl
$out = $out.Replace('{{LATESTVER}}', $latestVer)
$out = $out.Replace('{{LATESTDATE}}', $latestDate)
$out = $out.Replace('{{UPDATED}}', $updatedAt)
$out = $out.Replace('{{LATESTNOTE}}', $latestNote)
$out = $out.Replace('{{LATESTHTML}}', $latestHtml)
$out = $out.Replace('{{LATESTDIR}}', $latestDir)
$out = $out.Replace('{{LATESTDOCX}}', $latestDocx)
$out = $out.Replace('{{ROWS}}', $rows)
Write-Utf8NoBom (Join-Path $root 'index.html') $out
Write-Host "已重建首页（共 $($items.Count) 个版本）" -ForegroundColor Green

if ($RenderOnly) { return }

# ---------------------------------------------------------------- 3. 提交并推送
if (-not (Test-Path (Join-Path $root '.git'))) {
    Write-Warning "当前目录还不是 git 仓库，已跳过提交与推送。请先双击运行 首次配置.bat。"
    return
}

# git 往 stderr 写内容时，Stop 模式会中断脚本；这里局部降级并显式查退出码
function Invoke-Git {
    param([string[]]$Arguments)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw = & git @Arguments 2>&1
        $code = $LASTEXITCODE
        # ErrorRecord 的文案也要保留，否则真正的报错原因会被吞掉
        $text = ($raw | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { $_ } }) -join "`n"
        $text = $text.Trim()
    } finally { $ErrorActionPreference = $prev }
    return [pscustomobject]@{ Code = $code; Text = $text }
}

# 认证方式预检：GCM 若走 basic（用户名+密码）会被 GitHub 拒绝
# （Invalid username or token. Password authentication is not supported）
# 这里在未设置时锁成浏览器授权，避免再次弹用户名/密码。
$authMode = (Invoke-Git @('config', '--local', '--get', 'credential.gitHubAuthModes')).Text
if (-not $authMode) {
    Invoke-Git @('config', '--local', 'credential.gitHubAuthModes', 'browser') | Out-Null
    Write-Host "已设置 GitHub 认证方式为浏览器授权（避免弹出用户名/密码）" -ForegroundColor DarkGray
}

$message = if ($Note) { "发布 V$($latest.Ver)：$Note" } else { "发布 V$($latest.Ver)" }

$add = Invoke-Git @('add', '-A')
if ($add.Code -ne 0) { throw "git add 失败：$($add.Text)" }

# 没有实际改动时不硬提交（重复双击、同一分钟内重跑都会遇到），
# 但必须继续往下走 —— 本地可能还有从未推送成功的历史提交，这次要把它们推上去。
$staged = Invoke-Git @('diff', '--cached', '--quiet')
if ($staged.Code -eq 0) {
    Write-Host "本次没有内容变化，跳过提交，继续尝试推送。" -ForegroundColor Yellow
} else {
    $commit = Invoke-Git @('-c', 'http.sslBackend=openssl', 'commit', '-m', $message)
    if ($commit.Code -ne 0) { throw "git commit 失败：$($commit.Text)" }
    Write-Host "已提交：$message" -ForegroundColor Green
}
if ($NoPush) { Write-Host "已跳过推送（-NoPush）" -ForegroundColor Yellow; return }

$push = Invoke-Git @('-c', 'http.sslBackend=openssl', 'push', '-u', 'origin', 'HEAD')
if ($push.Code -ne 0) {
    Write-Host ""
    Write-Host "推送失败。内容已提交到本地，没有丢，按下面排查后重新双击本脚本即可：" -ForegroundColor Red
    Write-Host "  1) Authentication failed / Repository not found" -ForegroundColor Yellow
    Write-Host "     → 令牌过期，或令牌没勾选这个仓库：重新运行一次 首次配置.bat"
    Write-Host "  2) 弹出 Git Credential Manager 登录窗口" -ForegroundColor Yellow
    Write-Host "     → 选 Browser / 浏览器，在网页里点 Authorize 授权即可（推荐，不需要令牌）"
    Write-Host "  2b) 在窗口里被要求输入 Username / Password" -ForegroundColor Yellow
    Write-Host "     → Username 填 GitHub 账号名；Password 处粘贴令牌（不是账号密码）"
    Write-Host "  3) Connection was reset / timeout" -ForegroundColor Yellow
    Write-Host "     → 网络抖动，直接重跑本脚本"
    Write-Host "  4) schannel: AcquireCredentialsHandle failed" -ForegroundColor Yellow
    Write-Host "     → 在本目录执行：git config --local http.sslBackend openssl"
    Write-Host ""
    Write-Host "原始报错：$($push.Text)" -ForegroundColor DarkGray
    throw "推送未完成"
}

$remote = ((Invoke-Git @('remote', 'get-url', 'origin')).Text) -replace '\.git$', ''
$pages = $remote -replace 'https://github\.com/([^/]+)/([^/]+)', 'https://$1.github.io/$2/'
Write-Host ""
Write-Host "发布完成，稳定地址：" -ForegroundColor Green
Write-Host "  $pages" -ForegroundColor Cyan
Write-Host "  ${pages}latest.html" -ForegroundColor Cyan
Write-Host "（Pages 首次生效约需 1-2 分钟，之后每次发布约 30 秒）" -ForegroundColor DarkGray
