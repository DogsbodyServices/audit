# SQL Server Security Audit Script
# PowerShell script to collect SQL Server security audit information
# Requires SQL Server PowerShell module and appropriate permissions

param(
    [string]$ServerInstance = "localhost",
    [string]$Database = "master",
    [string]$ProductionDatabase = "",
    [PSCredential]$Credential = $null,
    [switch]$UseWindowsAuth
)

# Default to Windows Authentication if not specified
if (!$PSBoundParameters.ContainsKey('UseWindowsAuth')) {
    $UseWindowsAuth = $true
}

# Get current date for timestamping
$DATE = Get-Date -Format "yyyy-MM-dd"

# Save the current working directory before importing SQL modules
$OriginalLocation = Get-Location

# Import SQL Server module
try {
    Import-Module SqlServer -ErrorAction Stop
    Write-Host "SQL Server module loaded successfully" -ForegroundColor Green
} catch {
    try {
        Import-Module SQLPS -ErrorAction Stop
        Write-Host "SQLPS module loaded successfully" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: SQL Server PowerShell module not found. Please install SQL Server Management Tools." -ForegroundColor Red
        Write-Host "You can install it via: Install-Module -Name SqlServer" -ForegroundColor Yellow
        exit 1
    }
}

# Restore original location after module import (SQLPS changes location to SQLSERVER:\)
Set-Location $OriginalLocation

# Create audit outputs directory using absolute path
$AuditOutputsPath = Join-Path $OriginalLocation "audit_outputs"
New-Item -ItemType Directory -Force -Path $AuditOutputsPath | Out-Null

# Function to execute SQL query and save results
function Execute-SQLAudit {
    param(
        [string]$QueryName,
        [string]$Query,
        [string]$Description,
        [string]$TargetDatabase = $Database
    )
    
    Write-Host "==== $Description ====" -ForegroundColor Green
    $outputFile = Join-Path $AuditOutputsPath "sql_$($QueryName)_$DATE.txt"
    
    try {
        # Replace placeholder database names
        $processedQuery = $Query -replace '\{master or production database name\}', $TargetDatabase
        $processedQuery = $processedQuery -replace '\{production database name\}', $ProductionDatabase
        
        Write-Host "Executing query for: $Description" -ForegroundColor Yellow
        Write-Host "Target Database: $TargetDatabase" -ForegroundColor Gray
        
        # Execute the query
        if ($UseWindowsAuth) {
            $results = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $TargetDatabase -Query $processedQuery -ErrorAction Stop
        } else {
            $results = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $TargetDatabase -Query $processedQuery -Credential $Credential -ErrorAction Stop
        }
        
        # Format and save results
        $output = "==== $Description ====`n"
        $output += "Server: $ServerInstance`n"
        $output += "Database: $TargetDatabase`n"
        $output += "Query Executed: $($QueryName)`n"
        $output += "Date: $DATE`n"
        $output += "Time: $(Get-Date -Format 'HH:mm:ss')`n"
        $output += "=" * 50 + "`n`n"
        
        if ($results) {
            $output += ($results | Format-Table -AutoSize | Out-String)
            $output += "`n"
            $output += "Total records returned: $($results.Count)`n"
        } else {
            $output += "No results returned from query.`n"
        }
        
        $output | Out-File -FilePath $outputFile -Encoding UTF8
        Write-Host "Results saved to: $outputFile" -ForegroundColor Green
        
    } catch {
        $errorOutput = "==== ERROR: $Description ====`n"
        $errorOutput += "Server: $ServerInstance`n"
        $errorOutput += "Database: $TargetDatabase`n"
        $errorOutput += "Error: $($_.Exception.Message)`n"
        $errorOutput += "Date: $DATE`n"
        $errorOutput += "Time: $(Get-Date -Format 'HH:mm:ss')`n"
        
        $errorOutput | Out-File -FilePath $outputFile -Encoding UTF8
        Write-Host "ERROR executing query: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Error details saved to: $outputFile" -ForegroundColor Yellow
    }
}

Write-Host "Starting SQL Server Security Audit - $DATE" -ForegroundColor Yellow
Write-Host "Server Instance: $ServerInstance" -ForegroundColor Gray

if ($ProductionDatabase -eq "") {
    Write-Host "WARNING: No production database specified. Using 'master' for production database queries." -ForegroundColor Yellow
    $ProductionDatabase = "master"
}

# Test connection first
Write-Host "Testing SQL Server connection..." -ForegroundColor Yellow
try {
    if ($UseWindowsAuth) {
        $testResult = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database "master" -Query "SELECT @@SERVERNAME as ServerName, @@VERSION as Version" -ErrorAction Stop
    } else {
        $testResult = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database "master" -Query "SELECT @@SERVERNAME as ServerName, @@VERSION as Version" -Credential $Credential -ErrorAction Stop
    }
    Write-Host "Connection successful to: $($testResult.ServerName)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Cannot connect to SQL Server: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# SQL.05 - Authentication and Account Security
Write-Host "`n=== SQL.05 - Authentication and Account Security ===" -ForegroundColor Cyan

# SQL.05.1.1 - Windows Authentication Mode Check
Execute-SQLAudit -QueryName "auth_mode" -Description "SQL.05.1.1 - Windows Authentication Mode Check" -Query @"
Select @@servername AS [server_name], DB_NAME() AS [database_name], SERVERPROPERTY('IsIntegratedSecurityOnly') [Windows Only Authentication Mode];
"@

# SQL.05.1.2 - SQL Logins and Security Settings
Execute-SQLAudit -QueryName "sql_logins" -Description "SQL.05.1.2 - SQL Logins and Security Settings" -Query @"
Select @@servername AS [server_name], DB_NAME() AS [database_name], sp.name as Account, 
sp.[principal_id] [Account Principal ID], 
sp.[sid] [Account SID], 
sp.[type_desc] [Account Type], 
sp.[is_disabled] [Account Disabled], 
sl.denylogin [Account Deny Login], 
sl.hasaccess [Has Access], 
sp.[create_date] [Account Create Date], 
sp.[modify_date] [Account Modify Date], 
LOGINPROPERTY(sp.name,'PasswordLastSetTime') [Account Last Password Change Date], 
sp.is_policy_checked [Enforce Windows Password Policies?], 
sp.is_expiration_checked [Enforce Windows Expiration Policies?], 
case when (PWDCOMPARE('',sp.password_hash)=1) then 'Yes' Else 'No' End [Blank Password?]
FROM master.sys.sql_logins as sp LEFT JOIN
master.sys.syslogins as sl
on (sp.sid = sl.sid);
"@

# SQL.05.2.3 - Contained Database Authentication
Execute-SQLAudit -QueryName "contained_db_auth" -Description "SQL.05.2.3 - Contained Database Authentication Configuration" -Query @"
Select @@servername AS [server_name], DB_NAME() AS [database_name], c.[configuration_id],
	 c.[name],
	 c.[value_in_use],
	 c.[description]
FROM sys.configurations AS c
WHERE c.[name] = 'contained database authentication';
"@

# SQL.05.2.4 - Database Containment Levels
Execute-SQLAudit -QueryName "db_containment" -Description "SQL.05.2.4 - Database Containment Levels" -Query @"
Select @@servername AS [server_name], DB_NAME() AS [database_name], d.[name],
	 d.[database_id],
	 d.containment,
	 d.containment_desc
FROM sys.databases AS d
WHERE d.[name] NOT IN ('msdb','master','tempdb','model');
"@

# SQL.05.2.5 - Contained Database Users
if ($ProductionDatabase -ne "master") {
    Execute-SQLAudit -QueryName "contained_db_users" -Description "SQL.05.2.5 - Contained Database Users" -TargetDatabase $ProductionDatabase -Query @"
USE {production database name};

Select @@servername AS [server_name], DB_NAME() AS [database_name], dp.[name],
	 dp.[principal_id],
	 dp.[type],
	 dp.type_desc,
	 dp.create_date,
	 dp.modify_date,
	 dp.[authentication_type],
	 dp.[authentication_type_desc],
	 su.[hasdbaccess]
FROM sys.database_principals AS dp LEFT JOIN sys.sysusers AS su
	ON dp.[sid] = su.[sid]
WHERE dp.[type] != 'R'
	AND dp.[authentication_type_desc] IN ('DATABASE','WINDOWS')
	AND NOT EXISTS (Select 1 FROM sys.server_principals AS sp WHERE sp.[sid] = dp.[sid]);
"@
}

# SQL.06 - User Access and Permissions
Write-Host "`n=== SQL.06 - User Access and Permissions ===" -ForegroundColor Cyan

# SQL.06.1.1 - Server Principals (Users)
Execute-SQLAudit -QueryName "server_principals" -Description "SQL.06.1.1 - SQL Server Users and Logins" -Query @"
Select @@servername AS [server_name], DB_NAME() AS [database_name], sp.name as Grantee,
sp.[principal_id] [Grantee Principal ID], 
sp.[sid] [Grantee SID], 
sp.[type_desc] [Grantee Type], 
sp.[is_disabled] [Grantee Disabled], 
sl.denylogin [Grantee Deny Login], 
sl.hasaccess [Has Access], 
sp.[create_date] [Grantee Create Date], 
sp.[modify_date] [Account Modify Date], 
LOGINPROPERTY(sp.name,'PasswordLastSetTime') [Account Last Password Change Date], 
sp.[default_database_name] [Grantee Default Database]
FROM master.sys.server_principals as sp LEFT JOIN
master.sys.syslogins as sl
on (sp.sid = sl.sid);
"@

# SQL.06.2.2 - Server Role Members
Execute-SQLAudit -QueryName "server_roles" -Description "SQL.06.2.2 - SQL Server Role Memberships" -Query @"
Select @@servername AS [server_name], DB_NAME() AS [database_name], sp.name as Grantee,
sp.[principal_id] [Grantee Principal ID], 
sp.[sid] [Grantee SID], 
sp.[type_desc] [Grantee Type], 
sp.[is_disabled] [Grantee Disabled], 
sl.denylogin [Grantee Deny Login], 
sl.hasaccess [Has Access], 
sp.[create_date] [Grantee Create Date], 
sp.[modify_date] [Account Modify Date], 
LOGINPROPERTY(sp.name,'PasswordLastSetTime') [Account Last Password Change Date], 
sp.[default_database_name] [Grantee Default Database], 
sp2.name [Granted Role], 
sp2.[principal_id] [Role Principal ID], 
sp2.[sid] [Role SID], 
sp2.[create_date] [Role Create Date], 
sp2.[modify_date] [Role Modify Date]
FROM master.sys.server_role_members as srm, master.sys.server_principals as sp2, master.sys.server_principals as sp LEFT JOIN
master.sys.syslogins as sl
on (sp.sid = sl.sid)
WHERE ((sp.[principal_id] = srm.member_principal_id) AND
(sp2.principal_id = srm.role_principal_id));
"@

# SQL.06.2.3 - Server Permissions
Execute-SQLAudit -QueryName "server_permissions" -Description "SQL.06.2.3 - SQL Server Level Permissions" -Query @"
Select @@servername AS [server_name], DB_NAME() AS [database_name], sp.name as Grantee, 
sp.[principal_id] [Grantee Principal ID], 
sp.[sid] [Grantee SID], 
sp.[type_desc] [Grantee Type], 
sp.[is_disabled] [Grantee Disabled], 
sl.denylogin [Grantee Deny Login], 
sl.hasaccess [Has Access], 
sp.[create_date] [Grantee Create Date], 
sp.[modify_date] [Account Modify Date], 
LOGINPROPERTY(sp.name,'PasswordLastSetTime') [Account Last Password Change Date], 
srm.permission_name [Granted Permission], 
srm.class_desc [Securable Type], 
Case when srm.class = 101 Then SUSER_NAME(srm.major_id) END [Securable], 
srm.state_desc [State]
FROM master.sys.server_permissions as srm, master.sys.server_principals as sp LEFT JOIN
master.sys.syslogins as sl
on (sp.sid = sl.sid)
WHERE (sp.[principal_id] = srm.grantee_principal_id);
"@

# Database-level queries for master and production databases
$databasesToAudit = @("master")
if ($ProductionDatabase -ne "master") {
    $databasesToAudit += $ProductionDatabase
}

foreach ($dbName in $databasesToAudit) {
    Write-Host "`n--- Database Level Audit for: $dbName ---" -ForegroundColor Yellow
    
    # SQL.06.4.4 - Database Role Members
    Execute-SQLAudit -QueryName "db_roles_$($dbName.Replace(' ','_'))" -Description "SQL.06.4.4 - Database Role Memberships ($dbName)" -TargetDatabase $dbName -Query @"
USE {master or production database name};
Select @@servername AS [server_name], DB_NAME() AS [database_name], sp3.name [Grantee Login], 
sp.name as Grantee, 
sp.[principal_id] [Grantee Principal ID], 
sp.[sid] [Grantee SID], 
sp.[type_desc] [Grantee Type], 
sp3.[is_disabled] [Grantee Disabled], 
sl.denylogin [Grantee Deny Login], 
sl.hasaccess [Has Access], 
sp.[create_date] [Grantee Create Date], 
sp.[modify_date] [Account Modify Date], 
LOGINPROPERTY(sp3.name,'PasswordLastSetTime') [Account Last Password Change Date], 
CASE WHEN su.islogin = 0 THEN 'N\A - Role'
 WHEN su.[hasdbaccess] = 0 THEN 'No'
 WHEN su.[hasdbaccess] = 1 THEN 'Yes' END [Has Database Access], 
sp2.name [Granted Role], 
sp2.[principal_id] [Role Principal ID], 
sp2.[sid] [Role SID], 
sp2.[create_date] [Role Create Date], 
sp2.[modify_date] [Role Modify Date]
 FROM sys.database_role_members as srm, sys.database_principals as sp2, sys.sysusers as su, sys.database_principals as sp LEFT JOIN
 master.sys.syslogins as sl
 on (sp.sid = sl.sid)
 LEFT JOIN master.sys.server_principals as sp3
 on (sp.sid = sp3.sid)
WHERE ((sp.[principal_id] = srm.member_principal_id) AND
(sp2.principal_id = srm.role_principal_id) AND
(sp.principal_id = su.uid));
"@

    # SQL.06.5.5 - Database Permissions
    Execute-SQLAudit -QueryName "db_permissions_$($dbName.Replace(' ','_'))" -Description "SQL.06.5.5 - Database Level Permissions ($dbName)" -TargetDatabase $dbName -Query @"
USE {master or production database name};
Select @@servername AS [server_name], DB_NAME() AS [database_name], sp3.name [Grantee Login], 
sp.name as Grantee, 
sp.[principal_id] [Grantee Principal ID], 
sp.[sid] [Grantee SID], 
sp.[type_desc] [Grantee Type], 
sp3.[is_disabled] [Grantee Disabled], 
sl.denylogin [Grantee Deny Login], 
sl.hasaccess [Has Access], 
sp.[create_date] [Grantee Create Date], 
sp.[modify_date] [Account Modify Date], 
 LOGINPROPERTY(sp3.name,'PasswordLastSetTime') [Account Last Password Change Date], 
CASE WHEN su.islogin = 0 THEN 'N\A - Role'
 WHEN su.[hasdbaccess] = 0 THEN 'No'
 WHEN su.[hasdbaccess] = 1 THEN 'Yes' END [Has Database Access], 
database_permissions.permission_name [Permission], 
database_permissions.state_desc [Permission State], 
CASE WHEN class = 0 THEN DB_NAME() WHEN class = 1 
then case when minor_id = 0 then object_name(major_id) else (Select object_name(object_id) + '.'+ name FROM sys.columns where object_id = database_permissions.major_id and column_id = database_permissions.minor_id) 
end WHEN class = 3 THEN SCHEMA_NAME(major_id)
WHEN class = 4 THEN USER_NAME(major_id) END [Securable], 
CASE When ((database_permissions.class= 1) AND (database_permissions.minor_id <> 0)) then 'Column'
 WHEN ((database_permissions.class= 1) AND (database_permissions.minor_id = 0)) then 'Object'
 else database_permissions.class_desc END [Securable Description]
 FROM sys.database_permissions database_permissions, sys.sysusers as su, sys.database_principals as sp LEFT JOIN
 master.sys.syslogins as sl
 on (sp.sid = sl.sid)
 LEFT JOIN master.sys.server_principals as sp3
 on (sp.sid = sp3.sid)
WHERE ((sp.[principal_id] = database_permissions.grantee_principal_id) AND
(sp.principal_id = su.uid));
"@

    # SQL.06.6.6 - Database Owners
    Execute-SQLAudit -QueryName "db_owners_$($dbName.Replace(' ','_'))" -Description "SQL.06.6.6 - Database Owners ($dbName)" -TargetDatabase $dbName -Query @"
USE {master or production database name};
Select @@servername AS [server_name], DB_NAME() AS [database_name], sp.name [Database Owner], 
sp.[principal_id] [Database Owner Principal ID], 
sp.[sid] [Database Owner SID], 
sp.[type_desc] [Database Owner Type], 
sp.[is_disabled] [Database Owner Disabled], 
sl.denylogin [Database Owner Deny Login], 
sl.hasaccess [Has Access], 
sp.[create_date] [Database Owner Create Date], 
sp.[modify_date] [Database Owner Account Modify Date], 
LOGINPROPERTY(sp.name,'PasswordLastSetTime') [Account Last Password Change Date], 
db.name [Database]
FROM master.sys.databases as db, master.sys.server_principals as sp LEFT JOIN
master.sys.syslogins as sl
on (sp.sid = sl.sid)
WHERE (db.owner_sid = sl.sid);
"@

    # SQL.06.7.7 - Schema Owners
    Execute-SQLAudit -QueryName "schema_owners_$($dbName.Replace(' ','_'))" -Description "SQL.06.7.7 - Schema Owners ($dbName)" -TargetDatabase $dbName -Query @"
USE {master or production database name};
Select @@servername AS [server_name], DB_NAME() AS [database_name], sc.name [Schema Name], 
sc.schema_id [Schema ID], 
sp3.name [Schema Owner Login], 
sp.name [Schema Owner], 
sp.[principal_id] [Schema Owner Principal ID], 
sp.[sid] [Schema Owner SID], 
sp.[type_desc] [Schema Owner Type], 
sp3.[is_disabled] [Schema Owner Disabled], 
sl.denylogin [Schema Owner Deny Login], 
sl.hasaccess [Schema Owner Has Access], 
sp.[create_date] [Account Create Date], 
sp.[modify_date] [Account Modify Date], 
 LOGINPROPERTY(sp3.name,'PasswordLastSetTime') [Account Last Password Change Date], 
CASE WHEN su.islogin = 0 THEN 'N\A - Role'
 WHEN su.[hasdbaccess] = 0 THEN 'No'
 WHEN su.[hasdbaccess] = 1 THEN 'Yes' END [Has Database Access]
 FROM sys.schemas as sc INNER JOIN sys.database_principals as sp ON sc.[principal_id] = sp.[principal_id]
 INNER JOIN sys.sysusers as su ON sp.[principal_id] = su.uid 
 LEFT JOIN sys.syslogins as sl on (sp.sid = sl.sid)
 LEFT JOIN master.sys.server_principals as sp3 on (sp.sid = sp3.sid);
"@
}

# SQL.10 - Database Objects and Change Management
Write-Host "`n=== SQL.10 - Database Objects and Change Management ===" -ForegroundColor Cyan

foreach ($dbName in $databasesToAudit) {
    # SQL.10.1.1 - Database Objects
    Execute-SQLAudit -QueryName "db_objects_$($dbName.Replace(' ','_'))" -Description "SQL.10.1.1 - Database Objects for Change Management ($dbName)" -TargetDatabase $dbName -Query @"
USE {Master or production database name};
Select @@servername AS [server_name], DB_NAME() AS [database_name], SCHEMA_NAME(obj.[schema_id]) AS [schema],
	 obj.[name],
	 obj.[type],
	 obj.[type_desc],
	 obj.[create_date],
	 obj.[modify_date], 
obj.[is_ms_shipped]
FROM sys.objects AS obj
WHERE obj.[type] NOT IN ('F','PK','PG','ST','X');
"@
}

# Generate summary report
Write-Host "`n=== Generating Summary Report ===" -ForegroundColor Cyan
$summaryFile = Join-Path $AuditOutputsPath "sql_audit_summary_$DATE.txt"
$summary = @"
SQL Server Security Audit Summary
=================================
Date: $DATE
Time: $(Get-Date -Format 'HH:mm:ss')
Server Instance: $ServerInstance
Production Database: $ProductionDatabase
Authentication: $(if($UseWindowsAuth){'Windows Authentication'}else{'SQL Authentication'})

Audit Files Generated:
"@

Get-ChildItem $AuditOutputsPath -Filter "sql_*_$DATE.txt" | ForEach-Object {
    $summary += "`n- $($_.Name)"
}

$summary += @"

Notes:
- For any groups in the output, please provide a screenshot of the members of that group
- Export group members to Excel for documentation
- Review contained database authentication settings
- Check for accounts with blank passwords
- Verify appropriate role memberships and permissions
- Review database and schema ownership

Audit completed successfully.
"@

$summary | Out-File -FilePath $summaryFile -Encoding UTF8

Write-Host "`n=====================================" -ForegroundColor Green
Write-Host "SQL Server Security Audit Complete!" -ForegroundColor Green
Write-Host "Output files saved in audit_outputs/ directory" -ForegroundColor Green
Write-Host "Summary report: $summaryFile" -ForegroundColor Green
Write-Host "Files are timestamped with date: $DATE" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
