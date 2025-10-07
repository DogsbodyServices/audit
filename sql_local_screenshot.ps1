# SQL Server Local Screenshot Script
# Generates screenshots from collected SQL Server audit data

param(
    [string]$AuditRootDir = ""
)

$DATE = Get-Date -Format "yyyy-MM-dd"
New-Item -ItemType Directory -Force -Path "screenshots" | Out-Null

function Take-Screenshot {
    param(
        [string]$FilePath,
        [string]$ScreenshotName,
        [string]$Description
    )
    
    if (Test-Path $FilePath) {
        Write-Host "Taking screenshot of $Description..." -ForegroundColor Green
        Write-Host "  File: $FilePath" -ForegroundColor Gray
        
        # Open file in notepad for screenshot
        $notepadProcess = Start-Process notepad $FilePath -PassThru -WindowStyle Maximized
        
        # Wait for notepad to open and settle
        Start-Sleep -Seconds 3
        
        try {
            # Method 1: Using .NET to capture screen
            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -AssemblyName System.Drawing
            
            $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
            
            # Ensure the directory exists
            $screenshotDir = Split-Path $ScreenshotName -Parent
            if (!(Test-Path $screenshotDir)) {
                New-Item -ItemType Directory -Force -Path $screenshotDir | Out-Null
            }
            
            # Convert to absolute path to avoid GDI+ issues
            $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ScreenshotName)
            
            $bitmap.Save($fullPath, [System.Drawing.Imaging.ImageFormat]::Png)
            
            $graphics.Dispose()
            $bitmap.Dispose()
            
            Write-Host "Screenshot saved: $fullPath" -ForegroundColor Green
            
        } catch {
            Write-Host "Error taking screenshot: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Manual screenshot required for: $Description" -ForegroundColor Yellow
        }
        
        # Close notepad
        if ($notepadProcess -and !$notepadProcess.HasExited) {
            $notepadProcess.CloseMainWindow()
            Start-Sleep -Seconds 1
            if (!$notepadProcess.HasExited) {
                $notepadProcess.Kill()
            }
        }
        
    } else {
        Write-Host "File not found: $FilePath" -ForegroundColor Red
        Write-Host "  Current directory: $(Get-Location)" -ForegroundColor Gray
    }
}

Write-Host "Processing SQL Server audit results for screenshots..." -ForegroundColor Yellow

# Determine audit directories to process
$auditDirs = @()

if ($AuditRootDir -ne "" -and (Test-Path $AuditRootDir)) {
    # Multi-server audit results
    Write-Host "Processing multi-server audit results from: $AuditRootDir" -ForegroundColor Green
    $serverDirs = Get-ChildItem -Path $AuditRootDir -Directory
    foreach ($serverDir in $serverDirs) {
        if (Test-Path "$($serverDir.FullName)\audit_outputs") {
            $auditDirs += @{
                Name = $serverDir.Name
                Path = "$($serverDir.FullName)\audit_outputs"
                ScreenshotDir = "screenshots\sql_$($serverDir.Name)_$DATE"
            }
        }
    }
} elseif (Test-Path "audit_outputs") {
    # Local audit results
    Write-Host "Processing local SQL audit results..." -ForegroundColor Green
    $auditDirs += @{
        Name = "local"
        Path = "audit_outputs"
        ScreenshotDir = "screenshots\sql_local_$DATE"
    }
} else {
    Write-Host "No audit_outputs directory found. Please run the SQL audit script first." -ForegroundColor Red
    return
}

if ($auditDirs.Count -eq 0) {
    Write-Host "No SQL audit results found to screenshot." -ForegroundColor Yellow
    return
}

foreach ($auditDir in $auditDirs) {
    Write-Host "`nProcessing screenshots for $($auditDir.Name)..." -ForegroundColor Green
    
    New-Item -ItemType Directory -Force -Path $auditDir.ScreenshotDir | Out-Null
    
    # Get all SQL audit files
    $auditFiles = Get-ChildItem -Path $auditDir.Path -Filter "sql_*.txt"
    
    if ($auditFiles.Count -eq 0) {
        Write-Host "No SQL audit files found in $($auditDir.Path)" -ForegroundColor Yellow
        continue
    }
    
    Write-Host "Found $($auditFiles.Count) audit files to screenshot" -ForegroundColor Gray
    
    foreach ($auditFile in $auditFiles) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($auditFile.Name)
        $screenshotName = "$($auditDir.ScreenshotDir)\$baseName.png"
        
        # Create descriptive name based on file content
        $description = switch -Regex ($auditFile.Name) {
            "auth_mode" { "$($auditDir.Name) - Authentication Mode" }
            "sql_logins" { "$($auditDir.Name) - SQL Logins and Security" }
            "contained_db" { "$($auditDir.Name) - Contained Database Settings" }
            "db_containment" { "$($auditDir.Name) - Database Containment" }
            "contained_db_users" { "$($auditDir.Name) - Contained Database Users" }
            "server_principals" { "$($auditDir.Name) - Server Users and Logins" }
            "server_roles" { "$($auditDir.Name) - Server Role Memberships" }
            "server_permissions" { "$($auditDir.Name) - Server Level Permissions" }
            "db_roles" { "$($auditDir.Name) - Database Role Memberships" }
            "db_permissions" { "$($auditDir.Name) - Database Level Permissions" }
            "db_owners" { "$($auditDir.Name) - Database Owners" }
            "schema_owners" { "$($auditDir.Name) - Schema Owners" }
            "db_objects" { "$($auditDir.Name) - Database Objects" }
            "audit_summary" { "$($auditDir.Name) - Audit Summary" }
            default { "$($auditDir.Name) - $($auditFile.BaseName)" }
        }
        
        Take-Screenshot -FilePath $auditFile.FullName -ScreenshotName $screenshotName -Description $description
    }
    
    Write-Host "Screenshots processing complete for $($auditDir.Name)" -ForegroundColor Green
}

# Generate screenshot summary
$screenshotSummary = @"
SQL Server Audit Screenshots Summary
===================================
Date: $DATE
Time: $(Get-Date -Format 'HH:mm:ss')

Screenshots Generated:
"@

Get-ChildItem "screenshots" -Filter "sql_*.png" -Recurse | ForEach-Object {
    $screenshotSummary += "`n- $($_.FullName)"
}

$screenshotSummary += @"

Important Notes:
- Screenshots capture the audit results at the time of generation
- For groups identified in the results, you should:
  1. Take additional screenshots of group membership details
  2. Export group members to Excel as required by the audit process
  3. Document any unusual or concerning permissions

Key Areas to Review in Screenshots:
- SQL.05: Authentication settings and account security
- SQL.06: User access, roles, and permissions
- SQL.10: Database objects and change management

Next Steps:
1. Review all screenshots for security findings
2. Create Excel exports for group memberships
3. Document remediation actions for any issues found
4. Archive screenshots with audit documentation
"@

$screenshotSummary | Out-File -FilePath "screenshots\sql_screenshots_summary_$DATE.txt" -Encoding UTF8

Write-Host "`n=====================================" -ForegroundColor Green
Write-Host "SQL Server screenshots processing complete!" -ForegroundColor Green
Write-Host "Screenshots saved in screenshots\ directory" -ForegroundColor Green
Write-Host "Summary report: screenshots\sql_screenshots_summary_$DATE.txt" -ForegroundColor Green
Write-Host "Note: Some screenshots may require manual capture if automated screenshot failed" -ForegroundColor Yellow
Write-Host "=====================================" -ForegroundColor Green

Read-Host "Press Enter to continue..."
