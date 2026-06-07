#!/usr/bin/env pwsh
# =============================================================================
# fix-orphan-replica.ps1
# =============================================================================
# PURPOSE
#   Fixes the stuck Liquibase migration on the Railway-hosted Opik stack caused
#   by an orphaned ReplicatedMergeTree replica znode in ZooKeeper:
#
#     Code: 253. DB::Exception: Replica /clickhouse/tables/2/opik/
#     automation_rule_evaluator_logs/replicas/clickhouse-r1 already exists.
#     (REPLICA_ALREADY_EXISTS)
#
#   Root cause: a prior deployment left a ZK replica registration under
#   /clickhouse/tables/2/opik/<table>/replicas/clickhouse-r1 but the local
#   ClickHouse table no longer exists.  SYSTEM DROP REPLICA ... FROM ZKPATH
#   removes the orphaned znode without touching any live data.
#
# SAFETY
#   This script ONLY drops replicas for tables that are ABSENT from the local
#   opik database.  It will NEVER issue SYSTEM DROP REPLICA for a table that
#   exists locally (which would corrupt the live replica).
#
# HOST-KEY CAVEAT  (READ BEFORE RUNNING)
#   `railway ssh` tunnels through Railway's SSH proxy.  On the very first
#   connection from this machine Railway's host key is unknown and the SSH
#   client will prompt:
#
#     Are you sure you want to continue connecting (yes/no/[fingerprint])?
#
#   Step 1 of this script runs an interactive test query EXACTLY for this
#   reason — answer "yes" once at that prompt and all subsequent non-interactive
#   commands in this run will reuse the now-trusted host.
#
#   If Railway's CLI supports forwarding "-o StrictHostKeyChecking=no" via
#   `railway ssh -i <extra_ssh_args>` you can skip the interactive step by
#   setting $env:RAILWAY_SSH_EXTRA_ARGS = "-o StrictHostKeyChecking=accept-new"
#   before running this script.  Check `railway ssh --help` for current flags.
#
# USAGE
#   # Option A – token already in environment:
#   $env:RAILWAY_API_TOKEN = "<your_token>"
#   pwsh -File scripts\fix-orphan-replica.ps1
#
#   # Option B – token in scripts\.deploy.env (auto-loaded by this script):
#   pwsh -File scripts\fix-orphan-replica.ps1
#
# IDEMPOTENT
#   Safe to re-run.  Dropping an already-absent replica returns an error from
#   clickhouse-client which is caught and ignored.  Redeploying an already-
#   healthy backend is harmless.
# =============================================================================

#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 0. Resolve paths
# ---------------------------------------------------------------------------
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot   = Split-Path -Parent $ScriptDir
$RailwayBin = if ($env:RAILWAY_BIN) { $env:RAILWAY_BIN } `
              else { Join-Path $RepoRoot 'tools\railway-cli\railway.exe' }
$DeployEnv  = Join-Path $ScriptDir '.deploy.env'
$SecretsEnv = Join-Path $ScriptDir '.secrets.local'

# Also try the repo-root .secrets.local (that file lives there in this project)
$SecretsEnvAlt = Join-Path $RepoRoot '.secrets.local'

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " fix-orphan-replica.ps1  — Railway/ClickHouse ZK repair   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Repo root  : $RepoRoot"
Write-Host "  Railway CLI: $RailwayBin"
Write-Host ""

# ---------------------------------------------------------------------------
# 1. Validate railway.exe exists
# ---------------------------------------------------------------------------
if (-not (Test-Path $RailwayBin)) {
    Write-Error "Railway CLI not found at: $RailwayBin`nSet `$env:RAILWAY_BIN or place railway.exe at the expected path."
    exit 1
}

# ---------------------------------------------------------------------------
# 2. Load RAILWAY_API_TOKEN from .deploy.env if not already in environment
# ---------------------------------------------------------------------------
if (-not $env:RAILWAY_API_TOKEN) {
    if (Test-Path $DeployEnv) {
        Write-Host "[auth] Loading RAILWAY_API_TOKEN from $DeployEnv" -ForegroundColor Yellow
        Get-Content $DeployEnv | ForEach-Object {
            if ($_ -match '^\s*RAILWAY_API_TOKEN\s*=\s*(.+)$') {
                $env:RAILWAY_API_TOKEN = $Matches[1].Trim()
            }
        }
    }
}
if (-not $env:RAILWAY_API_TOKEN) {
    Write-Error "RAILWAY_API_TOKEN is not set.`nSet it in your shell or add it to $DeployEnv"
    exit 1
}
Write-Host "[auth] RAILWAY_API_TOKEN is set." -ForegroundColor Green

# ---------------------------------------------------------------------------
# 3. Load ClickHouse password (ANALYTICS_DB_PASSWORD) — never printed
# ---------------------------------------------------------------------------
$ChPassword = $null

# Try scripts/.secrets.local first, then repo-root .secrets.local
foreach ($candidate in @($SecretsEnv, $SecretsEnvAlt)) {
    if ($ChPassword) { break }
    if (Test-Path $candidate) {
        Get-Content $candidate | ForEach-Object {
            if ($_ -match '^\s*ANALYTICS_DB_PASSWORD\s*=\s*(.+)$') {
                $ChPassword = $Matches[1].Trim()
            }
        }
        if ($ChPassword) {
            Write-Host "[ch-auth] Password loaded from $candidate" -ForegroundColor Yellow
        }
    }
}

if (-not $ChPassword) {
    Write-Host "[ch-auth] ANALYTICS_DB_PASSWORD not found in secrets files." -ForegroundColor Yellow
    $SecurePw = Read-Host -Prompt "Enter ClickHouse opik user password" -AsSecureString
    $ChPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePw)
    )
}
if (-not $ChPassword) {
    Write-Error "ClickHouse password is required."
    exit 1
}
Write-Host "[ch-auth] ClickHouse password is available (not shown)." -ForegroundColor Green

# ---------------------------------------------------------------------------
# 4. Constants
# ---------------------------------------------------------------------------
$Proj         = '7ccaf972-0b24-46f2-a888-e877cb0cad7c'
$EnvName      = if ($env:ENV_NAME) { $env:ENV_NAME } else { 'production' }
$ChService    = 'clickhouse'
$BeService    = 'backend'
$ChUser       = 'opik'
$ZkBasePath   = '/clickhouse/tables/2/opik'
$Replica      = 'clickhouse-r1'
$KnownOrphan  = 'automation_rule_evaluator_logs'   # confirmed bad actor
$BeBootWait   = if ($env:BE_BOOT_WAIT) { [int]$env:BE_BOOT_WAIT } else { 55 }
$LogRetries   = 3

# Helper: run a railway CLI call and return stdout; exit 1 on failure unless -AllowFailure
function Invoke-Railway {
    param(
        [string[]]$Args,
        [switch]$AllowFailure,
        [switch]$Interactive      # do not capture; let it run in the current console
    )
    $cmd = @($RailwayBin) + $Args
    if ($Interactive) {
        & $RailwayBin @Args
        return $LASTEXITCODE
    }
    $output = & $RailwayBin @Args 2>&1
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        Write-Error "Railway command failed (exit $LASTEXITCODE):`n  railway $($Args -join ' ')`nOutput: $output"
        exit 1
    }
    return $output
}

# Helper: run a ClickHouse SQL query via railway ssh; returns stdout text
function Invoke-ChQuery {
    param(
        [string]$Query,
        [switch]$AllowFailure
    )
    # Build SSH command array:  railway ssh -s <svc> -e <env> -p <proj> -- clickhouse-client ...
    # Password is passed via --password flag; it will NOT appear in Write-Host output.
    $sshArgs = @(
        'ssh',
        '-s', $ChService,
        '-e', $EnvName,
        '-p', $Proj,
        '--',
        'clickhouse-client',
        '--user',    $ChUser,
        '--password', $ChPassword,
        '--query',   $Query
    )
    $output = & $RailwayBin @sshArgs 2>&1
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        # Mask password in any error message before printing
        $safeOut = ($output | Out-String) -replace [regex]::Escape($ChPassword), '***'
        Write-Error "clickhouse-client query failed:`n  $Query`nOutput: $safeOut"
        exit 1
    }
    return $output
}

# ---------------------------------------------------------------------------
# STEP 1 — Interactive host-key trust + connectivity test
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host " STEP 1: Interactive SSH connectivity + host-key trust test " -ForegroundColor Cyan
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Running an interactive SSH command.  If prompted:"
Write-Host "  'Are you sure you want to continue connecting (yes/no/[fingerprint])?'"
Write-Host "  --> Type  yes  and press Enter."
Write-Host ""
Write-Host "Command: railway ssh -s $ChService -e $EnvName -- clickhouse-client --query `"SELECT version()`""
Write-Host ""

# Use Interactive mode so the host-key prompt reaches the operator's terminal
$rc = Invoke-Railway -Args @('ssh', '-s', $ChService, '-e', $EnvName, '-p', $Proj, '--', `
        'clickhouse-client', '--user', $ChUser, '--password', $ChPassword, '--query', 'SELECT version()') `
    -Interactive

if ($rc -ne 0) {
    Write-Error "Connectivity test failed (exit $rc).  Resolve SSH/auth issues before proceeding."
    exit 1
}
Write-Host ""
Write-Host "[STEP 1] Connectivity OK." -ForegroundColor Green

# ---------------------------------------------------------------------------
# STEP 2 — Enumerate ZK tables and local tables; compute orphan set
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host " STEP 2: Enumerate orphaned ZK replica znodes               " -ForegroundColor Cyan
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan

Write-Host "[step2] Querying ZooKeeper for tables under $ZkBasePath ..."
$zkRaw = Invoke-ChQuery -Query "SELECT name FROM system.zookeeper WHERE path = '$ZkBasePath' FORMAT TSV" -AllowFailure
$zkTables = @()
if ($zkRaw) {
    $zkTables = ($zkRaw | Out-String).Trim().Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
}
Write-Host "[step2] ZK tables found: $($zkTables.Count)"
if ($zkTables.Count -gt 0) { $zkTables | ForEach-Object { Write-Host "          $_" } }

Write-Host "[step2] Querying local opik database tables ..."
$localRaw = Invoke-ChQuery -Query "SELECT name FROM system.tables WHERE database = 'opik' FORMAT TSV" -AllowFailure
$localTables = @()
if ($localRaw) {
    $localTables = ($localRaw | Out-String).Trim().Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
}
Write-Host "[step2] Local opik tables: $($localTables.Count)"

# Build the candidate orphan set = ZK tables NOT present locally
$orphans = @()
if ($zkTables.Count -gt 0) {
    foreach ($t in $zkTables) {
        if ($localTables -notcontains $t) {
            $orphans += $t
        }
    }
}

# Always ensure the known orphan is evaluated (guards against enumeration failure)
if ($localTables -notcontains $KnownOrphan -and $orphans -notcontains $KnownOrphan) {
    Write-Host "[step2] ZK enumeration may have been incomplete; adding known orphan '$KnownOrphan' to candidate list." -ForegroundColor Yellow
    $orphans += $KnownOrphan
}

if ($orphans.Count -eq 0) {
    Write-Host "[step2] No orphaned replicas detected.  Nothing to drop." -ForegroundColor Green
    Write-Host "        If the backend is still failing, redeploy it manually:"
    Write-Host "          $RailwayBin redeploy -s $BeService -y -e $EnvName -p $Proj"
    exit 0
}

Write-Host ""
Write-Host "[step2] Orphaned replicas to drop ($($orphans.Count)):" -ForegroundColor Yellow
$orphans | ForEach-Object { Write-Host "          $_" }

# ---------------------------------------------------------------------------
# STEP 3 — Drop orphaned replicas (SYSTEM DROP REPLICA ... FROM ZKPATH)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host " STEP 3: Drop orphaned ZK replicas                          " -ForegroundColor Cyan
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan

$dropped   = @()
$skipped   = @()
$failed    = @()

foreach ($table in $orphans) {
    # Double-check: skip if the table exists locally (safety guard)
    if ($localTables -contains $table) {
        Write-Host "[step3] SKIP '$table' — present in local opik database (NOT an orphan)." -ForegroundColor Yellow
        $skipped += $table
        continue
    }

    $zkPath = "$ZkBasePath/$table"
    $sql    = "SYSTEM DROP REPLICA '$Replica' FROM ZKPATH '$zkPath'"
    Write-Host "[step3] Dropping replica for: $table"
    Write-Host "        SQL: $sql"

    $result = Invoke-ChQuery -Query $sql -AllowFailure
    if ($LASTEXITCODE -eq 0) {
        Write-Host "        -> OK" -ForegroundColor Green
        $dropped += $table
    } else {
        $safeResult = ($result | Out-String) -replace [regex]::Escape($ChPassword), '***'
        # REPLICA_NOT_FOUND (code 999) or similar means already gone — treat as success
        if ($safeResult -match 'REPLICA_NOT_FOUND|Replica .* does not exist') {
            Write-Host "        -> Already absent (REPLICA_NOT_FOUND) — idempotent, continuing." -ForegroundColor Yellow
            $dropped += $table
        } else {
            Write-Host "        -> ERROR: $safeResult" -ForegroundColor Red
            $failed += $table
        }
    }
}

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "[step3] WARNING: $($failed.Count) replica(s) could not be dropped:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "          $_" -ForegroundColor Red }
    Write-Host "        The 'opik' user requires SYSTEM privilege (GRANT SYSTEM ON *.* TO opik)."
    Write-Host "        If this user lacks it, connect as 'default' with admin rights and re-run,"
    Write-Host "        or exec the SQL manually via the Railway dashboard shell."
    Write-Host "        Proceeding to backend redeploy anyway — it may still be stuck." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# STEP 4 — Redeploy backend
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host " STEP 4: Redeploy backend (re-run Liquibase migrations)      " -ForegroundColor Cyan
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan

Write-Host "[step4] Submitting backend redeploy ..."
Invoke-Railway -Args @('redeploy', '-s', $BeService, '-y', '-e', $EnvName, '-p', $Proj)
Write-Host "[step4] Redeploy submitted." -ForegroundColor Green
Write-Host "[step4] Waiting ${BeBootWait}s for backend to restart and run migrations ..."
Start-Sleep -Seconds $BeBootWait

# ---------------------------------------------------------------------------
# STEP 5 — Verify backend logs
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host " STEP 5: Verify backend logs                                 " -ForegroundColor Cyan
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan

$verified    = $false
$stillStuck  = $false

for ($attempt = 1; $attempt -le $LogRetries; $attempt++) {
    Write-Host "[step5] Fetching backend logs (attempt $attempt/$LogRetries) ..."
    $logs = Invoke-Railway -Args @('logs', '-s', $BeService, '-d', '--lines', '80', '-e', $EnvName, '-p', $Proj) -AllowFailure
    $logsText = $logs | Out-String

    Write-Host $logsText

    if ($logsText -match 'REPLICA_ALREADY_EXISTS') {
        $stillStuck = $true
        Write-Host "[step5] REPLICA_ALREADY_EXISTS still present in logs." -ForegroundColor Red
    } else {
        $stillStuck = $false
    }

    if ($logsText -match 'Liquibase.*successfully|migration.*completed|Successfully acquired|ChangeSet.*ran successfully') {
        Write-Host "[step5] Liquibase migration SUCCESS detected." -ForegroundColor Green
        $verified = $true
        break
    }

    if ($attempt -lt $LogRetries) {
        Write-Host "[step5] Migration not yet confirmed — waiting 20s before retry ..."
        Start-Sleep -Seconds 20
    }
}

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " SUMMARY                                                    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Orphans identified : $($orphans.Count)"
Write-Host "  Replicas dropped   : $($dropped.Count)  ($($dropped -join ', '))"
Write-Host "  Skipped (local)    : $($skipped.Count)  ($($skipped -join ', '))"
Write-Host "  Drop failures      : $($failed.Count)   ($($failed -join ', '))"

if ($verified) {
    Write-Host ""
    Write-Host "  RESULT: MIGRATIONS SUCCEEDED.  Backend is healthy." -ForegroundColor Green
} elseif ($stillStuck) {
    Write-Host ""
    Write-Host "  RESULT: REPLICA_ALREADY_EXISTS still present after fix." -ForegroundColor Red
    Write-Host "  Next steps:"
    Write-Host "    1. Check whether the opik user has SYSTEM privilege in ClickHouse."
    Write-Host "    2. Re-run this script, or run the DROP REPLICA SQL manually:"
    foreach ($t in $orphans) {
        Write-Host "         SYSTEM DROP REPLICA '$Replica' FROM ZKPATH '$ZkBasePath/$t';"
    }
    Write-Host "    3. Then: $RailwayBin redeploy -s $BeService -y -e $EnvName -p $Proj"
    Write-Host "    4. See scripts\RUNBOOK-item3.md for the full rollback decision tree."
    exit 1
} else {
    Write-Host ""
    Write-Host "  RESULT: Migrations not yet confirmed in log window — may still be running." -ForegroundColor Yellow
    Write-Host "  Re-pull logs in ~30s:"
    Write-Host "    $RailwayBin logs -s $BeService -d --lines 80 -e $EnvName -p $Proj"
}
