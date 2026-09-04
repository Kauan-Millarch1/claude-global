<#
.SYNOPSIS
  Installs this Claude Code global setup into ~/.claude.

.DESCRIPTION
  Copies the portable assets (CLAUDE.md, agents, skills, aura, statusline),
  installs the third-party plugins and skills from their own sources, and
  MERGES settings.template.json into an existing ~/.claude/settings.json
  instead of overwriting it.

  Everything it touches is backed up first. Run with -WhatIf to see the plan
  without changing anything.

.PARAMETER WhatIf
  Print what would happen. Change nothing.

.PARAMETER Force
  Overwrite existing files that differ, without asking.

.EXAMPLE
  .\install.ps1 -WhatIf
  .\install.ps1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeHome = Join-Path $HOME '.claude'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Say([string]$msg, [string]$color = 'Gray') { Write-Host $msg -ForegroundColor $color }
function Step([string]$msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
function Warn([string]$msg) { Write-Host "!! $msg" -ForegroundColor Yellow }
function Good([string]$msg) { Write-Host "ok $msg" -ForegroundColor Green }

# ---------------------------------------------------------------- preflight

Step 'Preflight'

$missing = @()
foreach ($t in @('node', 'git')) {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { $missing += $t }
}
if ($missing.Count) {
    throw "Required tool(s) not on PATH: $($missing -join ', '). Install them and re-run."
}
Good "node $(node --version), git present"

$optional = @{
    'claude'   = 'Claude Code CLI -- needed to install plugins (npm i -g @anthropic-ai/claude-code)'
    'rtk'      = 'RTK token proxy -- the PreToolUse hook calls it. Without it, every Bash call hits a failing hook; see README'
    'gh'       = 'GitHub CLI -- used by several skills'
    'codex'    = 'OpenAI Codex CLI -- only for the codex-* skills'
    'npx'      = 'npm -- needed to install skills from the skills.sh registry'
}
foreach ($k in $optional.Keys | Sort-Object) {
    if (Get-Command $k -ErrorAction SilentlyContinue) { Good "$k found" }
    else { Warn "$k missing -- $($optional[$k])" }
}

if (-not (Test-Path $ClaudeHome)) {
    if ($PSCmdlet.ShouldProcess($ClaudeHome, 'create directory')) {
        New-Item -ItemType Directory -Path $ClaudeHome -Force | Out-Null
    }
}

# ---------------------------------------------------------------- file copy

function Copy-Asset {
    param([string]$Relative, [switch]$Directory)

    $src = Join-Path $Here $Relative
    $dst = Join-Path $ClaudeHome $Relative
    if (-not (Test-Path $src)) { Warn "missing in repo: $Relative"; return }

    if (Test-Path $dst) {
        $same = $false
        if (-not $Directory) {
            try {
                $same = (Get-FileHash $src).Hash -eq (Get-FileHash $dst).Hash
            } catch { $same = $false }
        }
        if ($same) { Say "   unchanged  $Relative"; return }

        $backup = "$dst.bak-$Stamp"
        if ($PSCmdlet.ShouldProcess($dst, "back up to $(Split-Path -Leaf $backup)")) {
            if ($Directory) { Copy-Item $dst $backup -Recurse -Force }
            else { Copy-Item $dst $backup -Force }
            Warn "   backed up  $Relative -> $(Split-Path -Leaf $backup)"
        }
    }

    if ($PSCmdlet.ShouldProcess($dst, 'install')) {
        $parent = Split-Path -Parent $dst
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item $src $dst -Recurse -Force
        Good "  installed  $Relative"
    }
}

Step 'Installing portable assets'
Copy-Asset 'CLAUDE.md'
Copy-Asset 'RTK.md'
Copy-Asset 'agents'     -Directory
Copy-Asset 'aura'       -Directory
Copy-Asset 'statusline' -Directory

Step 'Installing skills from this repo'
$repoSkills = Get-ChildItem (Join-Path $Here 'skills') -Directory -ErrorAction SilentlyContinue
foreach ($s in $repoSkills) { Copy-Asset "skills\$($s.Name)" -Directory }

# ---------------------------------------------------------------- settings

Step 'Merging settings.json'

$templatePath = Join-Path $Here 'settings.template.json'
$settingsPath = Join-Path $ClaudeHome 'settings.json'

# Strip the _-prefixed documentation keys; they are for the reader, not the harness.
function Remove-DocKeys {
    param($Node)
    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        $out = [ordered]@{}
        foreach ($p in $Node.PSObject.Properties) {
            if ($p.Name.StartsWith('_')) { continue }
            $out[$p.Name] = Remove-DocKeys $p.Value
        }
        return [PSCustomObject]$out
    }
    if ($Node -is [System.Object[]]) { return @($Node | ForEach-Object { Remove-DocKeys $_ }) }
    return $Node
}

$template = Remove-DocKeys (Get-Content $templatePath -Raw | ConvertFrom-Json)

# Resolve the placeholder to this machine's real path. Do NOT pre-escape the
# backslashes: ConvertTo-Json escapes them on write, and doing both yields
# C:\\\\Users\\\\... which node cannot open.
$template.statusLine.command = $template.statusLine.command.Replace('__CLAUDE_HOME__', $ClaudeHome)

$existing = $null
if (Test-Path $settingsPath) {
    $backup = "$settingsPath.bak-$Stamp"
    if ($PSCmdlet.ShouldProcess($settingsPath, "back up to $(Split-Path -Leaf $backup)")) {
        Copy-Item $settingsPath $backup -Force
        Warn "   backed up  settings.json -> $(Split-Path -Leaf $backup)"
    }
    try { $existing = Get-Content $settingsPath -Raw | ConvertFrom-Json }
    catch { Warn '   existing settings.json is not valid JSON -- starting from the template alone' }
}

if ($null -eq $existing) {
    $merged = $template
} else {
    $merged = $existing
    foreach ($p in $template.PSObject.Properties) {
        if ($p.Name -eq 'permissions') { continue }   # handled below, additively
        $merged | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
    }

    # Permissions are additive and de-duplicated: never drop a rule the user already approved.
    if (-not $merged.permissions) {
        $merged | Add-Member -NotePropertyName 'permissions' -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    foreach ($bucket in @('allow', 'deny')) {
        $incoming = @($template.permissions.$bucket)
        if (-not $incoming) { continue }
        $current = @()
        if ($merged.permissions.PSObject.Properties.Name -contains $bucket) {
            $current = @($merged.permissions.$bucket)
        }
        $union = @($current + $incoming | Where-Object { $_ } | Select-Object -Unique)
        $merged.permissions | Add-Member -NotePropertyName $bucket -NotePropertyValue $union -Force
        Say "   permissions.$bucket : $($current.Count) kept + $($incoming.Count) offered = $($union.Count)"
    }
}

if ($PSCmdlet.ShouldProcess($settingsPath, 'write merged settings')) {
    $merged | ConvertTo-Json -Depth 32 | Out-File $settingsPath -Encoding utf8
    Good '  settings.json written'
}

# ---------------------------------------------------------- third party

Step 'Third-party plugins (installed from source, not copied)'

if (Get-Command claude -ErrorAction SilentlyContinue) {
    $marketplaces = @(
        'anthropics/claude-code',
        'obra/superpowers',
        'JuliusBrussee/caveman',
        'pbakaus/impeccable'
    )
    foreach ($m in $marketplaces) {
        if ($PSCmdlet.ShouldProcess($m, 'add marketplace')) {
            try { claude plugin marketplace add $m 2>&1 | Out-Null; Good "  marketplace $m" }
            catch { Warn "  marketplace $m failed: $($_.Exception.Message)" }
        }
    }
    $plugins = @(
        'superpowers@superpowers-dev',
        'caveman@caveman',
        'impeccable@impeccable',
        'learning-output-style@claude-code-plugins'
    )
    foreach ($p in $plugins) {
        if ($PSCmdlet.ShouldProcess($p, 'install plugin')) {
            try { claude plugin install $p 2>&1 | Out-Null; Good "  plugin $p" }
            catch { Warn "  plugin $p failed: $($_.Exception.Message)" }
        }
    }
} else {
    Warn 'claude CLI not found -- skipping plugins. Install it, then run:'
    Say  '     claude plugin marketplace add obra/superpowers'
    Say  '     claude plugin install superpowers@superpowers-dev'
    Say  '     (same for JuliusBrussee/caveman, pbakaus/impeccable, anthropics/claude-code)'
}

Step 'Third-party skills (installed from source, not copied)'

# Sources verified against the skills.sh lock file, not guessed. `skills add`
# works at repo level, so each of these may bring siblings along; that is fine
# and visible in the output.
if (Get-Command npx -ErrorAction SilentlyContinue) {
    $registry = @(
        'mattpocock/skills',      # grilling, grill-me, grill-with-docs, handoff, domain-modeling, tdd
        'vercel-labs/skills',     # find-skills
        'supabase/agent-skills'   # supabase, supabase-postgres-best-practices
    )
    foreach ($r in $registry) {
        if ($PSCmdlet.ShouldProcess($r, 'npx skills add')) {
            try { npx --yes skills add $r 2>&1 | Out-Null; Good "  skills add $r" }
            catch { Warn "  skills add $r failed -- add it manually: npx skills add $r" }
        }
    }
    Say '   not scripted: wshobson/agents (kpi-dashboard-design) -- large repo, add it by hand if you want it'
} else {
    Warn 'npx not found -- skipping registry skills'
}

# will-pagane/claude-setup is not on the registry: it is a clone plus a copy.
$setup = Join-Path $ClaudeHome 'claude-setup'
if (Test-Path $setup) {
    Say '   already cloned  claude-setup'
} elseif ($PSCmdlet.ShouldProcess('will-pagane/claude-setup', 'clone into .claude\claude-setup')) {
    try { git clone --depth 1 https://github.com/will-pagane/claude-setup.git $setup 2>&1 | Out-Null; Good '  cloned claude-setup' }
    catch { Warn "  clone claude-setup failed: $($_.Exception.Message)" }
}

$setupSkills = Join-Path $setup 'skills'
if (Test-Path $setupSkills) {
    foreach ($s in Get-ChildItem $setupSkills -Directory) {
        $dst = Join-Path (Join-Path $ClaudeHome 'skills') $s.Name
        if ((Test-Path $dst) -and -not $Force) { Say "   kept existing  skills\$($s.Name)"; continue }
        if ($PSCmdlet.ShouldProcess($dst, 'copy skill from claude-setup')) {
            Copy-Item $s.FullName $dst -Recurse -Force
            Good "  skill $($s.Name)  (from claude-setup)"
        }
    }
}

Step 'eyes -- real-browser UI review'
$eyes = Join-Path (Join-Path $ClaudeHome 'skills') 'eyes'
if (Test-Path $eyes) {
    Say '   already present'
} elseif ($PSCmdlet.ShouldProcess('Kauan-Millarch1/claude-eyes', 'clone + npm install')) {
    try {
        git clone --depth 1 https://github.com/Kauan-Millarch1/claude-eyes.git $eyes 2>&1 | Out-Null
        Push-Location (Join-Path $eyes 'runtime')
        npm install --silent 2>&1 | Out-Null
        Pop-Location
        Good '  eyes installed (needs Chrome or Edge at runtime)'
    } catch { Warn "  eyes failed: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------- done

Step 'Done'
Write-Host ''
Write-Host 'Next:' -ForegroundColor White
Say '  1. Restart Claude Code so it re-reads ~/.claude/settings.json.'
Say '  2. Install rtk, or remove the PreToolUse block from ~/.claude/settings.json.'
Say '     Leaving the hook in place without the binary makes every Bash call fail.'
Say '  3. Run  /help  and check the skills list. Then try  /grill-me  on any plan.'
Write-Host ''
Say "Backups from this run are suffixed .bak-$Stamp"
