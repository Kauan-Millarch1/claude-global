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

# The PreToolUse hook shells out to rtk on every Bash call. Installing it
# without the binary would put a failing hook in front of every command, so the
# hook is only written when rtk actually resolves.
$HasRtk = [bool](Get-Command rtk -ErrorAction SilentlyContinue)

if (-not (Test-Path $ClaudeHome)) {
    if ($PSCmdlet.ShouldProcess($ClaudeHome, 'create directory')) {
        New-Item -ItemType Directory -Path $ClaudeHome -Force | Out-Null
    }
}

# ---------------------------------------------------------------- file copy

function Copy-Asset {
    param(
        [string]$Relative,
        [switch]$Directory,
        # Never clobber this file. If the user already has a different one, the
        # incoming version lands beside it for them to merge by hand. Used for
        # CLAUDE.md, which is the user's own standing instructions -- replacing
        # it silently takes their rules out of service.
        [switch]$Preserve
    )

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

        if ($Preserve -and -not $Force) {
            $side = "$dst.from-claude-global"
            if ($PSCmdlet.ShouldProcess($side, 'write alongside instead of overwriting')) {
                Copy-Item $src $side -Force
                Warn "   KEPT YOURS  $Relative"
                Say  "     You already have a different $Relative. Yours is untouched."
                Say  "     The incoming one is at: $(Split-Path -Leaf $side)"
                Say  '     Merge what you want, then delete it. Re-run with -Force to overwrite instead.'
            }
            return
        }

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
Copy-Asset 'CLAUDE.md' -Preserve
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

if (-not $HasRtk) {
    $template.hooks.PSObject.Properties.Remove('PreToolUse')
    Warn '   rtk not on PATH -- skipping the PreToolUse hook (it would fail on every Bash call).'
    Say  '     Install rtk later, then add this to hooks in ~/.claude/settings.json:'
    Say  '       "PreToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "rtk hook claude" }] }]'
}

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
    # Output is NOT silenced: these can prompt, and a swallowed prompt looks
    # exactly like a hang. Native commands do not throw, so check the exit code.
    foreach ($m in $marketplaces) {
        if ($PSCmdlet.ShouldProcess($m, 'add marketplace')) {
            claude plugin marketplace add $m
            if ($LASTEXITCODE -eq 0) { Good "  marketplace $m" }
            else { Warn "  marketplace $m exited $LASTEXITCODE -- add it by hand: claude plugin marketplace add $m" }
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
            claude plugin install $p
            if ($LASTEXITCODE -eq 0) { Good "  plugin $p" }
            else { Warn "  plugin $p exited $LASTEXITCODE -- install it by hand: claude plugin install $p" }
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
            npx --yes skills add $r
            if ($LASTEXITCODE -eq 0) { Good "  skills add $r" }
            else { Warn "  skills add $r exited $LASTEXITCODE -- add it by hand: npx skills add $r" }
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
    git clone --depth 1 https://github.com/will-pagane/claude-setup.git $setup
    if ($LASTEXITCODE -eq 0) { Good '  cloned claude-setup' }
    else { Warn "  clone claude-setup exited $LASTEXITCODE -- skills from it will be missing" }
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
    git clone --depth 1 https://github.com/Kauan-Millarch1/claude-eyes.git $eyes
    if ($LASTEXITCODE -ne 0) {
        Warn "  clone claude-eyes exited $LASTEXITCODE -- skipping"
    } else {
        Push-Location (Join-Path $eyes 'runtime')
        npm install
        $npmExit = $LASTEXITCODE
        Pop-Location
        if ($npmExit -eq 0) { Good '  eyes installed (needs Chrome or Edge at runtime)' }
        else { Warn "  npm install for eyes exited $npmExit -- run it by hand in $eyes\runtime" }
    }
}

# ---------------------------------------------------------------- done

Step 'Done'
Write-Host ''
Write-Host '  ================================================================' -ForegroundColor Yellow
Write-Host '   RESTART CLAUDE CODE NOW. Nothing above is active until you do.' -ForegroundColor Yellow
Write-Host '   settings.json, CLAUDE.md and plugins are read once, at startup.' -ForegroundColor Yellow
Write-Host '   A running session -- including the one that ran this script --' -ForegroundColor Yellow
Write-Host '   will not pick any of it up.' -ForegroundColor Yellow
Write-Host '  ================================================================' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Then:' -ForegroundColor White
Say '  - Run  /help  and check the skills list. Try  /grill-me  on any plan.'
if (-not $HasRtk) {
    Say '  - rtk was not found, so no Bash hook was installed. Nothing is broken;'
    Say '    you just do not get output compression. See README to add it later.'
}
$kept = Get-ChildItem $ClaudeHome -Filter '*.from-claude-global' -ErrorAction SilentlyContinue
if ($kept) {
    Write-Host ''
    Warn 'You already had your own versions of these -- they were NOT replaced:'
    foreach ($k in $kept) { Say "    $($k.Name)   <- merge what you want, then delete it" }
}
Write-Host ''
Say "Backups from this run are suffixed .bak-$Stamp"
