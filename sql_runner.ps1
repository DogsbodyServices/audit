# SQL Server Remote Audit Runner
# Executes SQL audit script on remote SQL servers

param(
    [string]$ServersFile = "sql_servers.txt",
    [string]$ProductionDatabase = "",
    [PSCredential]$Credential = $null,
    [switch]$UseWindowsAuth
)

$DATE = Get-Date -Format "yyyy-MM-dd"
Write-Host "SQL Server Remote Audit Runner - $DATE" -ForegroundColor Yellow

# Check if servers file exists
if (!(Test-Path $ServersFile)) {
    Write-Host "Creating example servers file: $ServersFile" -ForegroundColor Yellow
    @"
# SQL Server instances to audit (one per line)
# Format: ServerName\InstanceName or ServerName (for default instance)
# Examples:
# SQL01\PROD
# SQL02.domain.com
# localhost
# 192.168.1.100\SQLEXPRESS

localhost
"@ | Out-File -FilePath $ServersFile -Encoding UTF8
    
    Write-Host "Please edit $ServersFile and add your SQL Server instances, then run this script again." -ForegroundColor Yellow
    return
}

# Read server list
$servers = Get-Content $ServersFile | Where-Object { $_ -notmatch '^#' -and $_.Trim() -ne '' }

if ($servers.Count -eq 0) {
    Write-Host "No servers found in $ServersFile. Please add server instances." -ForegroundColor Red
    return
}

Write-Host "Found $($servers.Count) SQL Server instance(s) to audit:" -ForegroundColor Green
$servers | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }

# Create main audit results directory
$auditRootDir = "sql_audit_results_$DATE"
New-Item -ItemType Directory -Force -Path $auditRootDir | Out-Null

# Get credentials if not using Windows auth
if (!$UseWindowsAuth -and !$Credential) {
    $Credential = Get-Credential -Message "Enter SQL Server credentials"
    if (!$Credential) {
        Write-Host "Credentials required for SQL authentication. Exiting." -ForegroundColor Red
        return
    }
}

# Audit each server
foreach ($server in $servers) {
    $serverName = $server.Replace('\', '_').Replace('.', '_')
    $serverAuditDir = "$auditRootDir\$serverName"
    
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "Auditing SQL Server: $server" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    # Create server-specific directory
    New-Item -ItemType Directory -Force -Path $serverAuditDir | Out-Null
    
    # Change to server directory
    Push-Location $serverAuditDir
    
    try {
        # Copy the audit script to server directory
        Copy-Item "..\..\sql_audit.ps1" -Destination "." -Force
        
        # Prepare parameters for audit script
        $auditParams = @{
            ServerInstance = $server
        }
        
        if ($ProductionDatabase -ne "") {
            $auditParams.ProductionDatabase = $ProductionDatabase
        }
        
        if ($UseWindowsAuth) {
            $auditParams.UseWindowsAuth = $true
        } else {
            $auditParams.UseWindowsAuth = $false
            $auditParams.Credential = $Credential
        }
        
        # Execute the audit
        Write-Host "Starting audit for $server..." -ForegroundColor Yellow
        & ".\sql_audit.ps1" @auditParams
        
        # Create server-specific summary
        $serverSummary = @"
SQL Server Audit Summary for: $server
=====================================
Date: $DATE
Time: $(Get-Date -Format 'HH:mm:ss')
Status: Completed Successfully

Files Generated:
"@
        
        Get-ChildItem "audit_outputs" -Filter "*.txt" -ErrorAction SilentlyContinue | ForEach-Object {
            $serverSummary += "`n- $($_.Name)"
        }
        
        $serverSummary | Out-File -FilePath "audit_summary_$serverName.txt" -Encoding UTF8
        
        Write-Host "Audit completed for $server" -ForegroundColor Green
        
    } catch {
        Write-Host "ERROR auditing $server`: $($_.Exception.Message)" -ForegroundColor Red
        
        # Create error summary
        $errorSummary = @"
SQL Server Audit Summary for: $server
=====================================
Date: $DATE
Time: $(Get-Date -Format 'HH:mm:ss')
Status: FAILED

Error: $($_.Exception.Message)

Possible causes:
- Server not accessible
- Insufficient permissions
- SQL Server service not running
- Network connectivity issues
- Authentication failure
"@
        
        $errorSummary | Out-File -FilePath "audit_error_$serverName.txt" -Encoding UTF8
    } finally {
        Pop-Location
    }
}

# Generate overall summary
Write-Host "`n" + "="*60 -ForegroundColor Green
Write-Host "SQL Server Remote Audit Complete" -ForegroundColor Green
Write-Host "="*60 -ForegroundColor Green

$overallSummary = @"
SQL Server Multi-Server Audit Summary
=====================================
Date: $DATE
Time: $(Get-Date -Format 'HH:mm:ss')
Servers Audited: $($servers.Count)

Server Results:
"@

foreach ($server in $servers) {
    $serverName = $server.Replace('\', '_').Replace('.', '_')
    $serverDir = "$auditRootDir\$serverName"
    
    if (Test-Path "$serverDir\audit_outputs") {
        $fileCount = (Get-ChildItem "$serverDir\audit_outputs" -Filter "*.txt" -ErrorAction SilentlyContinue).Count
        $overallSummary += "`n- $server`: SUCCESS ($fileCount files generated)"
    } else {
        $overallSummary += "`n- $server`: FAILED (check error logs)"
    }
}

$overallSummary += @"

Notes:
- Individual server results are in: $auditRootDir\<servername>\
- Review each server's audit files for security findings
- Pay special attention to:
  * Accounts with blank passwords
  * Excessive permissions
  * Unusual role memberships
  * Database ownership issues

Next Steps:
1. Review audit files for each server
2. Generate screenshots for group memberships
3. Export group members to Excel as required
4. Document findings and remediation actions
"@

$overallSummary | Out-File -FilePath "$auditRootDir\overall_audit_summary.txt" -Encoding UTF8

Write-Host "Overall summary saved to: $auditRootDir\overall_audit_summary.txt" -ForegroundColor Green
Write-Host "Individual server results in: $auditRootDir\<servername>\" -ForegroundColor Green

# Offer to create screenshots
Write-Host "`nWould you like to generate screenshots of the audit results? (Y/N): " -ForegroundColor Yellow -NoNewline
$response = Read-Host

if ($response -match '^[Yy]') {
    if (Test-Path "sql_local_screenshot.ps1") {
        Write-Host "Running screenshot generation..." -ForegroundColor Yellow
        & ".\sql_local_screenshot.ps1" -AuditRootDir $auditRootDir
    } else {
        Write-Host "Screenshot script not found. Create sql_local_screenshot.ps1 to enable screenshot generation." -ForegroundColor Yellow
    }
}
