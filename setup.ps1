#Requires -Version 5.1
<#
  setup.ps1 —— 一次性把本地仓库接到 GitHub
  （双击 首次配置.bat 时自动调用本脚本）

  前提：你已经在 GitHub 网页上创建好仓库（不要勾选 Add README）。
#>
[CmdletBinding()]
param(
    [string]$User,
    [string]$Repo,
    [string]$Token,
    [string]$Email,
    [switch]$SkipToken
)

# 原生命令(git)往 stderr 写东西时，若 ErrorActionPreference=Stop 会直接中断脚本。
# 这里用 Continue，并在每次调用后显式检查退出码。
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

function Invoke-Git {
    param([string[]]$Arguments)
    $raw = & git @Arguments 2>&1
    $code = $LASTEXITCODE
    $text = (($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n").Trim()
    return [pscustomobject]@{ Code = $code; Text = $text }
}
function Invoke-GitChecked {
    param([string]$Label, [string[]]$Arguments)
    $result = Invoke-Git $Arguments
    if ($result.Code -ne 0) { throw "$Label 失败：$($result.Text)" }
    return $result.Text
}

Write-Host ""
Write-Host "=== 演示站首次配置 ===" -ForegroundColor Cyan
Write-Host ""

if (-not $User) { $User = (Read-Host "请输入 GitHub 账号名（或组织名）").Trim() }
if (-not $Repo) { $Repo = (Read-Host "请输入仓库名（例如 gd-safety-quality-demo）").Trim() }
if (-not $User -or -not $Repo) { throw "账号名和仓库名不能为空" }

# 1. 先初始化仓库：--local 配置必须写在已有的仓库里，所以 init 必须最先做
if (-not (Test-Path (Join-Path $root '.git'))) {
    $init = Invoke-Git @('init', '-b', 'main')
    if ($init.Code -ne 0) {
        Invoke-GitChecked 'git init' @('init') | Out-Null
        Invoke-GitChecked '设置默认分支 main' @('symbolic-ref', 'HEAD', 'refs/heads/main') | Out-Null
    }
    Write-Host "已初始化本地仓库" -ForegroundColor Green
} else {
    Write-Host "本地仓库已存在，跳过初始化" -ForegroundColor DarkGray
}

# 2. TLS 后端（本机 schannel 握手会失败，必须用 openssl）
Invoke-GitChecked '设置 TLS 后端' @('config', '--local', 'http.sslBackend', 'openssl') | Out-Null

# 3. 提交身份
$name = (Invoke-Git @('config', '--local', 'user.name')).Text
if (-not $name) {
    $name = Read-Host "请输入提交用的姓名（例如 张三）"
    Invoke-GitChecked '保存姓名' @('config', '--local', 'user.name', $name) | Out-Null
}
if (-not $Email) {
    $cur = (Invoke-Git @('config', '--local', 'user.email')).Text
    if (-not $cur) {
        $Email = Read-Host "请输入提交用的邮箱"
        Invoke-GitChecked '保存邮箱' @('config', '--local', 'user.email', $Email) | Out-Null
    }
} else {
    Invoke-GitChecked '保存邮箱' @('config', '--local', 'user.email', $Email) | Out-Null
}

# 4. 远端地址
$url = "https://github.com/$User/$Repo.git"
$existing = (Invoke-Git @('remote', 'get-url', 'origin')).Text
if ($existing) {
    Invoke-GitChecked '更新远端地址' @('remote', 'set-url', 'origin', $url) | Out-Null
} else {
    Invoke-GitChecked '添加远端地址' @('remote', 'add', 'origin', $url) | Out-Null
}
Write-Host "远端已设置：$url" -ForegroundColor Green

# 5. 凭证（PAT，可选）
if (-not $Token -and -not $SkipToken) {
    Write-Host ""
    Write-Host "推送凭证有两种方式：" -ForegroundColor Yellow
    Write-Host "  · 直接回车跳过 → 首次推送时弹出浏览器登录窗口（推荐，不用建令牌）"
    Write-Host "  · 粘贴令牌     → 现在就存好，以后静默推送"
    Write-Host "  令牌入口：https://github.com/settings/personal-access-tokens/new"
    Write-Host "  权限只需：Repository access 选中本仓库；Permissions → Contents = Read and write"
    Write-Host ""
    $secure = Read-Host "粘贴令牌（输入内容不显示）" -AsSecureString
    if ($secure.Length -gt 0) {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $Token = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}

if ($Token) {
    $helper = (Invoke-Git @('config', '--get', 'credential.helper')).Text
    if (-not $helper) {
        Invoke-Git @('config', '--local', 'credential.helper', 'manager') | Out-Null
        $helper = (Invoke-Git @('config', '--get', 'credential.helper')).Text
        if (-not $helper) {
            Invoke-Git @('config', '--local', 'credential.helper', 'manager-core') | Out-Null
            $helper = (Invoke-Git @('config', '--get', 'credential.helper')).Text
        }
    }
    if ($helper) { Write-Host "凭证助手：$helper" -ForegroundColor DarkGray }

    $payload = "protocol=https`nhost=github.com`nusername=$User`npassword=$Token`n`n"
    $payload | & git credential approve 2>&1 | Out-Null
    Write-Host "令牌已交给凭据管理器保存" -ForegroundColor Green
    if (-not $helper) {
        Write-Host "提示：未检测到凭证助手。若推送时要求输入 Username / Password，就填账号名 + 粘贴令牌。" -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "已跳过令牌 —— 这条路更省事，推荐：" -ForegroundColor Yellow
    Write-Host "  下一步跑 发布更新.bat 时会弹出登录窗口，选 Browser / 浏览器，"
    Write-Host "  在打开的网页里用 GitHub 账号点一下 Authorize 授权即可，不用建令牌。"
    Write-Host "  登录成功后凭证自动保存，以后发布不用再登录。"
}

# 6. 当前分支（还没有提交时 HEAD 不存在，用 symbolic-ref 才安全）
$branch = (Invoke-Git @('symbolic-ref', '--short', 'HEAD')).Text
if ($branch) { Write-Host "当前分支：$branch" -ForegroundColor DarkGray }

Write-Host ""
Write-Host "配置完成。下一步：" -ForegroundColor Cyan
Write-Host "  1) 双击 发布更新.bat 推送内容（跑完仓库里才会有 main 分支）"
Write-Host "  2) 再去仓库 Settings → Pages 选 main + / (root)，此时才选得到"
Write-Host ""
