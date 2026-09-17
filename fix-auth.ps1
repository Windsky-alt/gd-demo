#Requires -Version 5.1
<#
  fix-auth.ps1 —— 修复 GitHub 推送认证
  （双击 修复登录.bat 时自动调用本脚本）

  适用症状：
    remote: Invalid username or token. Password authentication is not supported
    for Git operations.
    fatal: Authentication failed for 'https://github.com/...'

  原因：Git Credential Manager 走了 basic（用户名+密码）方式，而 GitHub 早已
        不接受账号密码。这里把它锁成浏览器授权，就不会再问用户名/密码。
#>
[CmdletBinding()]
param(
    [switch]$UseDeviceCode
)

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

function Invoke-Git {
    param([string[]]$Arguments)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw = & git @Arguments 2>&1
        $code = $LASTEXITCODE
        $text = ($raw | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { $_ } }) -join "`n"
        $text = $text.Trim()
    } finally { $ErrorActionPreference = $prev }
    return [pscustomobject]@{ Code = $code; Text = $text }
}

Write-Host ""
Write-Host "=== 修复 GitHub 推送认证 ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path (Join-Path $root '.git'))) {
    Write-Warning "当前目录不是 git 仓库，请先双击 首次配置.bat。"
    return
}

# 1. 清掉可能残留的无效凭证（没有也无害）
$payload = "protocol=https`nhost=github.com`n`n"
$payload | & git credential reject 2>&1 | Out-Null
Write-Host "已清理 github.com 的旧凭证（若有）" -ForegroundColor Green

# 2. 锁定认证方式：浏览器授权，不再提供用户名/密码
$mode = if ($UseDeviceCode) { 'device' } else { 'browser' }
$set = Invoke-Git @('config', '--local', 'credential.gitHubAuthModes', $mode)
if ($set.Code -ne 0) { throw "写入配置失败：$($set.Text)" }
$current = (Invoke-Git @('config', '--local', '--get', 'credential.gitHubAuthModes')).Text
Write-Host "已设置 GitHub 认证方式：$current" -ForegroundColor Green

# 3. 顺带确认 TLS 后端（本机 schannel 会握手失败）
Invoke-Git @('config', '--local', 'http.sslBackend', 'openssl') | Out-Null

Write-Host ""
Write-Host "接下来：" -ForegroundColor Cyan
if ($UseDeviceCode) {
    Write-Host "  双击 发布更新.bat，屏幕会显示一个 8 位代码；"
    Write-Host "  打开 https://github.com/login/device 输入该代码并授权。"
} else {
    Write-Host "  双击 发布更新.bat，会自动打开浏览器；"
    Write-Host "  用 GitHub 账号登录后点 Authorize 授权即可。"
}
Write-Host ""
Write-Host "如果浏览器授权方式不成功，改用设备码方式：" -ForegroundColor DarkGray
Write-Host "  .\fix-auth.ps1 -UseDeviceCode" -ForegroundColor DarkGray
Write-Host ""
