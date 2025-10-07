# Windows Audit Script
# PowerShell script to collect Windows security audit information
# Run with Administrator privileges

# Get current date for timestamping
$DATE = Get-Date -Format "yyyy-MM-dd"

# Create audit outputs directory
New-Item -ItemType Directory -Force -Path "audit_outputs" | Out-Null

# Function to audit and save output
function Audit-AndSave {
    param(
        [string]$Description,
        [scriptblock]$Command,
        [string]$OutputFile
    )
    
    Write-Host "==== $Description ====" -ForegroundColor Green
    $output = "==== $Description ====`n"
    
    try {
        $result = & $Command
        if ($result) {
            $output += ($result | Out-String)
        } else {
            $output += "No results found or command returned empty.`n"
        }
    } catch {
        $output += "Error executing command: $($_.Exception.Message)`n"
    }
    
    $output | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Host "Completed: $Description"
}

Write-Host "Starting Windows Security Audit - $DATE" -ForegroundColor Yellow

# 1. PRIVILEGED ACCESS - Administrators Group Members
Audit-AndSave -Description "Local Administrators Group Members" -OutputFile "audit_outputs/administrators_group_$DATE.txt" -Command {
    Write-Output "Local Administrators Group Members:"
    Write-Output "=================================="
    
    try {
        # Method 1: Use WMI method (most reliable)
        Write-Output "Using WMI to retrieve Administrators group members:"
        $adminMembers = Get-WmiObject -Class Win32_GroupUser | Where-Object {
            $_.GroupComponent -like '*Administrators*'
        } | Select-Object PartComponent
        
        if ($adminMembers) {
            Write-Output "`nAdministrators Group Members:"
            Write-Output "-----------------------------"
            foreach ($member in $adminMembers) {
                $memberPath = $member.PartComponent
                Write-Output "Member: $memberPath"
                
                # Try to extract just the account name for cleaner display
                if ($memberPath -match 'Name="([^"]+)"') {
                    $accountName = $matches[1]
                    Write-Output "  Account Name: $accountName"
                }
                Write-Output ""
            }
            
            Write-Output "Total members found: $($adminMembers.Count)"
        } else {
            Write-Output "No members found in Administrators group using WMI method."
        }
        
    } catch {
        Write-Output "WMI method failed: $($_.Exception.Message)"
        Write-Output "`nTrying fallback method using Get-LocalGroupMember..."
        
        # Method 2: Try Get-LocalGroupMember as fallback
        try {
            Get-LocalGroupMember -Group "Administrators" | Select-Object Name, ObjectClass, PrincipalSource | Format-Table -AutoSize
        } catch {
            Write-Output "Get-LocalGroupMember also failed: $($_.Exception.Message)"
            Write-Output "`nTrying net localgroup as final fallback..."
            
            # Method 3: Use net localgroup as final fallback
            try {
                $netOutput = net localgroup administrators
                Write-Output "Raw net localgroup output:"
                $netOutput | ForEach-Object { Write-Output $_ }
            } catch {
                Write-Output "All methods failed. Manual verification required for Administrators group membership"
                Write-Output "Error: $($_.Exception.Message)"
            }
        }
    }
}

# 2. PRIVILEGED ACCESS - Nested Groups in Administrators (if any)
Audit-AndSave -Description "Nested Groups Analysis in Administrators" -OutputFile "audit_outputs/administrators_nested_groups_$DATE.txt" -Command {
    Write-Output "Nested Groups Analysis in Administrators:"
    Write-Output "======================================="
    
    try {
        # Use WMI to get Administrators group members
        $adminMembers = Get-WmiObject -Class Win32_GroupUser | Where-Object {
            $_.GroupComponent -like '*Administrators*'
        } | Select-Object PartComponent
        
        if ($adminMembers) {
            Write-Output "Analyzing members for nested groups..."
            Write-Output "-------------------------------------"
            
            $groupsFound = 0
            foreach ($member in $adminMembers) {
                $memberPath = $member.PartComponent
                
                # Extract account name and domain
                if ($memberPath -match 'Name="([^"]+)"') {
                    $accountName = $matches[1]
                    
                    # Check if this looks like a group and search across domains
                    # Try to get more info about this account
                    try {
                        # Extract domain and account name if it contains domain info
                        $domainName = ""
                        $groupName = $accountName
                        
                        if ($accountName -match "^(.+)\\(.+)$") {
                            $domainName = $matches[1]
                            $groupName = $matches[2]
                        }
                        
                        Write-Output "Checking account: $accountName (Domain: $domainName, Group: $groupName)"
                        
                        # Try to determine if it's a group by checking Win32_Group locally first
                        $isGroup = Get-WmiObject -Class Win32_Group -Filter "Name='$groupName'" -ErrorAction SilentlyContinue
                        
                        # If not found locally and we have a domain, try searching in the domain
                        if (-not $isGroup -and $domainName) {
                            Write-Output "  Not found locally, checking domain: $domainName"
                            
                            # Try different domain search approaches for causey.com and cloud.local
                            try {
                                # Method 1: Try ADSI for domain groups
                                $domainPath = "WinNT://$domainName"
                                $domain = [ADSI]$domainPath
                                $group = $domain.Children.Find($groupName, "Group")
                                if ($group) {
                                    $isGroup = $true
                                    Write-Output "  Found as domain group in $domainName"
                                }
                            } catch {
                                Write-Output "  ADSI search failed for $domainName/$groupName`: $($_.Exception.Message)"
                            }
                        }
                        
                        if ($isGroup) {
                            Write-Output "=== Found nested group: $accountName ==="
                            $groupsFound++
                            
                            # Try to get members of this nested group using multiple methods
                            try {
                                # Method 1: Local WMI search
                                $nestedMembers = Get-WmiObject -Class Win32_GroupUser | Where-Object {
                                    $_.GroupComponent -like "*Name=`"$groupName`"*"
                                }
                                
                                if ($nestedMembers) {
                                    Write-Output "Members of nested group '$accountName' (Local WMI):"
                                    foreach ($nestedMember in $nestedMembers) {
                                        Write-Output "  $($nestedMember.PartComponent)"
                                    }
                                } else {
                                    Write-Output "No local members found via WMI for '$accountName'"
                                    
                                    # Method 2: Try ADSI for domain group members
                                    if ($domainName) {
                                        try {
                                            Write-Output "Trying ADSI to get members of domain group '$domainName\\$groupName':"
                                            $domainPath = "WinNT://$domainName"
                                            $domain = [ADSI]$domainPath
                                            $group = $domain.Children.Find($groupName, "Group")
                                            
                                            if ($group) {
                                                $members = $group.Invoke("Members")
                                                $memberCount = 0
                                                foreach ($member in $members) {
                                                    $memberPath = $member.GetType().InvokeMember("AdsPath", "GetProperty", $null, $member, $null)
                                                    $memberName = $member.GetType().InvokeMember("Name", "GetProperty", $null, $member, $null)
                                                    Write-Output "  Member: $memberName ($memberPath)"
                                                    $memberCount++
                                                }
                                                if ($memberCount -eq 0) {
                                                    Write-Output "  Group '$accountName' exists but has no members or members are not accessible"
                                                }
                                            }
                                        } catch {
                                            Write-Output "  ADSI member enumeration failed for $domainName\$groupName`: $($_.Exception.Message)"
                                        }
                                    }
                                }
                            } catch {
                                Write-Output "Could not retrieve members of nested group '$accountName': $($_.Exception.Message)"
                            }
                            Write-Output ""
                        } else {
                            # Check if it looks like it might be a group based on naming patterns
                            if ($accountName -match "\\|Domain|Group|Admin" -or $accountName -like "*Admins*" -or $accountName -like "*Users*" -or $domainName) {
                                Write-Output "Potential group member (could not verify as group): $accountName"
                                if ($domainName) {
                                    Write-Output "  Appears to be from domain: $domainName"
                                }
                            }
                        }
                    } catch {
                        Write-Output "Error analyzing account '$accountName': $($_.Exception.Message)"
                        # If we can't determine the type, just log it as a potential group
                        if ($accountName -match "\\|Domain|Group" -or $accountName -like "*Admins*") {
                            Write-Output "Potential group member (error during verification): $accountName"
                        }
                    }
                }
            }
            
            if ($groupsFound -eq 0) {
                Write-Output "No nested groups found in Administrators group."
                Write-Output "All members appear to be individual user accounts."
            } else {
                Write-Output "Total nested groups found: $groupsFound"
            }
        } else {
            Write-Output "Could not retrieve Administrators group members for analysis."
        }
        
    } catch {
        Write-Output "WMI-based nested group analysis failed: $($_.Exception.Message)"
        Write-Output "Manual verification required for nested group analysis"
        
        # Fallback: Try the original method
        try {
            Write-Output "`nTrying fallback method with Get-LocalGroupMember..."
            $adminMembers = Get-LocalGroupMember -Group "Administrators"
            $nestedGroups = $adminMembers | Where-Object {$_.ObjectClass -eq "Group"}
            if ($nestedGroups) {
                foreach ($group in $nestedGroups) {
                    Write-Output "=== Members of nested group: $($group.Name) ==="
                    Get-LocalGroupMember -Group $group.Name | Select-Object Name, ObjectClass, PrincipalSource | Format-Table -AutoSize
                }
            } else {
                Write-Output "No nested groups found using fallback method."
            }
        } catch {
            Write-Output "Fallback method also failed: $($_.Exception.Message)"
        }
    }
}

# 3. PRIVILEGED ACCESS - User Rights Assignment (Restore files and Take ownership)
Audit-AndSave -Description "User Rights Assignment - Restore Files and Directories" -OutputFile "audit_outputs/user_rights_restore_files_$DATE.txt" -Command {
    Write-Output "User Rights Assignment - Restore Files and Directories:"
    Write-Output "======================================================"
    
    # Create a unique temporary file path
    $tempFile = "$env:TEMP\secpol_$(Get-Random).cfg"
    
    try {
        # Export security policy
        $seceditResult = secedit /export /cfg "$tempFile" /quiet 2>&1
        
        if (Test-Path $tempFile) {
            $secpol = Get-Content $tempFile
            $restoreFilesLine = $secpol | Where-Object {$_ -like "*SeRestorePrivilege*"}
            if ($restoreFilesLine) {
                Write-Output "Restore files and directories privilege:"
                Write-Output $restoreFilesLine
                
                # Decode the SIDs if possible
                if ($restoreFilesLine -match "= (.+)") {
                    $sids = $matches[1] -split ","
                    Write-Output "`nDecoded accounts:"
                    foreach ($sid in $sids) {
                        $sid = $sid.Trim()
                        if ($sid.StartsWith("*")) {
                            $sid = $sid.Substring(1)
                        }
                        try {
                            $account = (New-Object System.Security.Principal.SecurityIdentifier($sid)).Translate([System.Security.Principal.NTAccount])
                            Write-Output "  $sid = $($account.Value)"
                        } catch {
                            Write-Output "  $sid = (Could not resolve)"
                        }
                    }
                }
            } else {
                Write-Output "No accounts found with Restore files and directories privilege"
            }
        } else {
            Write-Output "Failed to export security policy. Error: $seceditResult"
            Write-Output "This may require running as Administrator or the Local Security Policy may not be accessible."
        }
    } catch {
        Write-Output "Error accessing security policy: $($_.Exception.Message)"
    } finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

Audit-AndSave -Description "User Rights Assignment - Take Ownership" -OutputFile "audit_outputs/user_rights_take_ownership_$DATE.txt" -Command {
    Write-Output "User Rights Assignment - Take Ownership:"
    Write-Output "======================================"
    
    # Create a unique temporary file path
    $tempFile = "$env:TEMP\secpol_$(Get-Random).cfg"
    
    try {
        # Export security policy
        $seceditResult = secedit /export /cfg "$tempFile" /quiet 2>&1
        
        if (Test-Path $tempFile) {
            $secpol = Get-Content $tempFile
            $takeOwnershipLine = $secpol | Where-Object {$_ -like "*SeTakeOwnershipPrivilege*"}
            if ($takeOwnershipLine) {
                Write-Output "Take ownership of files or other objects privilege:"
                Write-Output $takeOwnershipLine
                
                # Decode the SIDs if possible
                if ($takeOwnershipLine -match "= (.+)") {
                    $sids = $matches[1] -split ","
                    Write-Output "`nDecoded accounts:"
                    foreach ($sid in $sids) {
                        $sid = $sid.Trim()
                        if ($sid.StartsWith("*")) {
                            $sid = $sid.Substring(1)
                        }
                        try {
                            $account = (New-Object System.Security.Principal.SecurityIdentifier($sid)).Translate([System.Security.Principal.NTAccount])
                            Write-Output "  $sid = $($account.Value)"
                        } catch {
                            Write-Output "  $sid = (Could not resolve)"
                        }
                    }
                }
            } else {
                Write-Output "No accounts found with Take ownership privilege"
            }
        } else {
            Write-Output "Failed to export security policy. Error: $seceditResult"
            Write-Output "This may require running as Administrator or the Local Security Policy may not be accessible."
        }
    } catch {
        Write-Output "Error accessing security policy: $($_.Exception.Message)"
    } finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

# 4. PASSWORD POLICIES
Audit-AndSave -Description "Password Policy Settings" -OutputFile "audit_outputs/password_policy_$DATE.txt" -Command {
    Write-Output "Password Policy Settings:"
    Write-Output "========================"
    
    # Method 1: Use net accounts command
    try {
        Write-Output "Password Policy from 'net accounts':"
        Write-Output "====================================="
        $passwordPolicy = net accounts 2>&1
        $passwordPolicy | ForEach-Object { Write-Output $_ }
    } catch {
        Write-Output "net accounts command failed: $($_.Exception.Message)"
    }
    
    # Method 2: Try secedit for detailed policy
    Write-Output "`nDetailed Local Security Policy (if available):"
    Write-Output "=============================================="
    
    $tempFile = "$env:TEMP\secpol_$(Get-Random).cfg"
    
    try {
        $seceditResult = secedit /export /cfg "$tempFile" /quiet 2>&1
        
        if (Test-Path $tempFile) {
            $secpol = Get-Content $tempFile
            
            # Extract password policy settings
            $passwordSettings = @(
                "MinimumPasswordLength",
                "MaximumPasswordAge", 
                "MinimumPasswordAge",
                "PasswordHistorySize",
                "PasswordComplexity",
                "LockoutBadCount",
                "ResetLockoutCount", 
                "LockoutDuration"
            )
            
            Write-Output "Security Policy Settings:"
            foreach ($setting in $passwordSettings) {
                $line = $secpol | Where-Object {$_ -like "*$setting*"}
                if ($line) {
                    Write-Output "  $line"
                }
            }
        } else {
            Write-Output "Could not export security policy: $seceditResult"
        }
    } catch {
        Write-Output "Error accessing detailed security policy: $($_.Exception.Message)"
    } finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
    
    # Method 3: Try Registry for some settings
    Write-Output "`nPassword Policy from Registry (where available):"
    Write-Output "==============================================="
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
        if (Test-Path $regPath) {
            $lsaSettings = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
            if ($lsaSettings) {
                Write-Output "LSA Settings from Registry:"
                $lsaSettings | Select-Object * | Format-List
            }
        }
    } catch {
        Write-Output "Could not access registry settings: $($_.Exception.Message)"
    }
}

# 5. PASSWORD NEVER EXPIRES ACCOUNTS
Audit-AndSave -Description "Accounts with Password Never Expires" -OutputFile "audit_outputs/password_never_expires_$DATE.txt" -Command {
    Write-Output "Local accounts with 'Password Never Expires' set:"
    Write-Output "================================================"
    Get-LocalUser | Where-Object {$_.PasswordExpires -eq $null} | Select-Object Name, Enabled, LastLogon, PasswordLastSet | Format-Table -AutoSize
    
    Write-Output "`nActive Directory accounts (if domain joined):"
    Write-Output "=============================================="
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Get-ADUser -Filter {PasswordNeverExpires -eq $true} -Properties PasswordNeverExpires, PasswordLastSet, LastLogonDate | Select-Object Name, Enabled, PasswordLastSet, LastLogonDate | Format-Table -AutoSize
    } catch {
        Write-Output "ActiveDirectory module not available or not domain joined. Skipping AD account check."
    }
}

# 6. INSTALLED PATCHES/UPDATES (from April 1, 2025 to present)
Audit-AndSave -Description "Installed Updates from April 1, 2025 to Present" -OutputFile "audit_outputs/installed_patches_$DATE.txt" -Command {
    $startDate = Get-Date "2025-04-01"
    $endDate = Get-Date
    
    Write-Output "Installed Updates from $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd')):"
    Write-Output "=============================================================================="
    
    # Method 1: Using Get-HotFix (most reliable for older systems)
    Write-Output "`n=== Hotfixes (Get-HotFix) ==="
    Get-HotFix | Where-Object {$_.InstalledOn -ge $startDate} | Sort-Object InstalledOn -Descending | Select-Object HotFixID, Description, InstalledBy, InstalledOn | Format-Table -AutoSize
    
    # Method 2: Using Windows Update Session (more comprehensive)
    Write-Output "`n=== Windows Updates (Windows Update API) ==="
    try {
        $Session = New-Object -ComObject Microsoft.Update.Session
        $Searcher = $Session.CreateUpdateSearcher()
        $HistoryCount = $Searcher.GetTotalHistoryCount()
        
        if ($HistoryCount -gt 0) {
            $History = $Searcher.QueryHistory(0, $HistoryCount)
            $RecentUpdates = $History | Where-Object {$_.Date -ge $startDate} | Sort-Object Date -Descending
            
            foreach ($Update in $RecentUpdates) {
                Write-Output "Title: $($Update.Title)"
                Write-Output "Date: $($Update.Date)"
                Write-Output "Result: $($Update.ResultCode)"
                Write-Output "Description: $($Update.Description)"
                Write-Output "---"
            }
        } else {
            Write-Output "No update history found"
        }
    } catch {
        Write-Output "Could not access Windows Update history: $($_.Exception.Message)"
    }
    
    # Method 3: Using WMIC (for older systems)
    Write-Output "`n=== Quick Patch List (WMIC) ==="
    try {
        $wmicOutput = wmic qfe get HotFixID,InstalledOn,Description /format:csv 2>$null
        if ($wmicOutput) {
            $wmicOutput | Where-Object {$_ -ne ""} | ForEach-Object {
                if ($_ -match '\d{1,2}/\d{1,2}/\d{4}') {
                    Write-Output $_
                }
            }
        }
    } catch {
        Write-Output "WMIC command failed: $($_.Exception.Message)"
    }
}

# 7. SYSTEM INFORMATION SUMMARY
Audit-AndSave -Description "System Information Summary" -OutputFile "audit_outputs/system_info_$DATE.txt" -Command {
    Write-Output "System Information Summary"
    Write-Output "========================="
    Write-Output "Computer Name: $env:COMPUTERNAME"
    Write-Output "Domain: $env:USERDOMAIN"
    Write-Output "OS Version: $([System.Environment]::OSVersion.VersionString)"
    Write-Output "PowerShell Version: $($PSVersionTable.PSVersion)"
    Write-Output "Audit Date: $DATE"
    Write-Output "Audit Time: $(Get-Date -Format 'HH:mm:ss')"
    Write-Output ""
    
    systeminfo | Select-String "OS Name|OS Version|System Boot Time|Domain|Registered Owner|Total Physical Memory"
}

Write-Host "`nWindows Security Audit Complete!" -ForegroundColor Green
Write-Host "Output files saved in audit_outputs/ directory" -ForegroundColor Green
Write-Host "Files are timestamped with date: $DATE" -ForegroundColor Green

# SIG # Begin signature block
# MIInuAYJKoZIhvcNAQcCoIInqTCCJ6UCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBIo+RJa3+//Q1p
# uVhiSF8n300lqyBJ3FznTQ826/1xaaCCDIIwggYaMIIEAqADAgECAhBiHW0MUgGe
# O5B5FSCJIRwKMA0GCSqGSIb3DQEBDAUAMFYxCzAJBgNVBAYTAkdCMRgwFgYDVQQK
# Ew9TZWN0aWdvIExpbWl0ZWQxLTArBgNVBAMTJFNlY3RpZ28gUHVibGljIENvZGUg
# U2lnbmluZyBSb290IFI0NjAeFw0yMTAzMjIwMDAwMDBaFw0zNjAzMjEyMzU5NTla
# MFQxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzApBgNV
# BAMTIlNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBDQSBSMzYwggGiMA0GCSqG
# SIb3DQEBAQUAA4IBjwAwggGKAoIBgQCbK51T+jU/jmAGQ2rAz/V/9shTUxjIztNs
# fvxYB5UXeWUzCxEeAEZGbEN4QMgCsJLZUKhWThj/yPqy0iSZhXkZ6Pg2A2NVDgFi
# gOMYzB2OKhdqfWGVoYW3haT29PSTahYkwmMv0b/83nbeECbiMXhSOtbam+/36F09
# fy1tsB8je/RV0mIk8XL/tfCK6cPuYHE215wzrK0h1SWHTxPbPuYkRdkP05ZwmRmT
# nAO5/arnY83jeNzhP06ShdnRqtZlV59+8yv+KIhE5ILMqgOZYAENHNX9SJDm+qxp
# 4VqpB3MV/h53yl41aHU5pledi9lCBbH9JeIkNFICiVHNkRmq4TpxtwfvjsUedyz8
# rNyfQJy/aOs5b4s+ac7IH60B+Ja7TVM+EKv1WuTGwcLmoU3FpOFMbmPj8pz44MPZ
# 1f9+YEQIQty/NQd/2yGgW+ufflcZ/ZE9o1M7a5Jnqf2i2/uMSWymR8r2oQBMdlyh
# 2n5HirY4jKnFH/9gRvd+QOfdRrJZb1sCAwEAAaOCAWQwggFgMB8GA1UdIwQYMBaA
# FDLrkpr/NZZILyhAQnAgNpFcF4XmMB0GA1UdDgQWBBQPKssghyi47G9IritUpimq
# F6TNDDAOBgNVHQ8BAf8EBAMCAYYwEgYDVR0TAQH/BAgwBgEB/wIBADATBgNVHSUE
# DDAKBggrBgEFBQcDAzAbBgNVHSAEFDASMAYGBFUdIAAwCAYGZ4EMAQQBMEsGA1Ud
# HwREMEIwQKA+oDyGOmh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1B1Ymxp
# Y0NvZGVTaWduaW5nUm9vdFI0Ni5jcmwwewYIKwYBBQUHAQEEbzBtMEYGCCsGAQUF
# BzAChjpodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2ln
# bmluZ1Jvb3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdv
# LmNvbTANBgkqhkiG9w0BAQwFAAOCAgEABv+C4XdjNm57oRUgmxP/BP6YdURhw1aV
# cdGRP4Wh60BAscjW4HL9hcpkOTz5jUug2oeunbYAowbFC2AKK+cMcXIBD0ZdOaWT
# syNyBBsMLHqafvIhrCymlaS98+QpoBCyKppP0OcxYEdU0hpsaqBBIZOtBajjcw5+
# w/KeFvPYfLF/ldYpmlG+vd0xqlqd099iChnyIMvY5HexjO2AmtsbpVn0OhNcWbWD
# RF/3sBp6fWXhz7DcML4iTAWS+MVXeNLj1lJziVKEoroGs9Mlizg0bUMbOalOhOfC
# ipnx8CaLZeVme5yELg09Jlo8BMe80jO37PU8ejfkP9/uPak7VLwELKxAMcJszkye
# iaerlphwoKx1uHRzNyE6bxuSKcutisqmKL5OTunAvtONEoteSiabkPVSZ2z76mKn
# zAfZxCl/3dq3dUNw4rg3sTCggkHSRqTqlLMS7gjrhTqBmzu1L90Y1KWN/Y5JKdGv
# spbOrTfOXyXvmPL6E52z1NZJ6ctuMFBQZH3pwWvqURR8AgQdULUvrxjUYbHHj95E
# jza63zdrEcxWLDX6xWls/GDnVNueKjWUH3fTv1Y8Wdho698YADR7TNx8X8z2Bev6
# SivBBOHY+uqiirZtg0y9ShQoPzmCcn63Syatatvx157YK9hlcPmVoa1oDE5/L9Uo
# 2bC5a4CH2RwwggZgMIIEyKADAgECAhAQz5q4xih22hjWkHba8NMdMA0GCSqGSIb3
# DQEBDAUAMFQxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQx
# KzApBgNVBAMTIlNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBDQSBSMzYwHhcN
# MjQxMTI3MDAwMDAwWhcNMjYxMTI3MjM1OTU5WjB3MQswCQYDVQQGEwJHQjEYMBYG
# A1UECAwPQnVja2luZ2hhbXNoaXJlMSYwJAYDVQQKDB1DQVVTRVdBWSBURUNITk9M
# T0dJRVMgTElNSVRFRDEmMCQGA1UEAwwdQ0FVU0VXQVkgVEVDSE5PTE9HSUVTIExJ
# TUlURUQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDBe3lXcZbexaCk
# rkv9NO41074rQx6ut+hOQYG+beX9PkM/R0bbegI45w3cxHAsEAPQM28VdjWead1E
# x4ZtBYV+agUkEvbhktubDo7+eqsgHjXe6HY2f+Zzumry9tIxeTxmkUwCTr2zBUeM
# EFrlsjF7woX8WmUFiyZ9oTtJPyKAXbguKuZzgbqC644rXPHFJEG8QrP/cbMgw4t2
# FQlFc2ZZe9Sd6i0RRGoKHirEEA+MEY1tI00iz7qAdhTT2C55I3HAUcb+0oUfapVK
# JrZkSaAX9w5ylkCAO4jIdv7EbErvcXey/COrTp+1YNyltI7aSQMlioyl42iz3LAK
# NvqcEJebkpJCGcrWUSuvRFovM9KYdr+bvDv3Z+5UN0AKIZv3/B83r4xyblgKdfbx
# gr9CxnHXuR789xS31/HlC5Hv6lcx1YzAYUCK5C6ZlLjwpQ3kYg2spI9WZwZBlJyB
# Ai9C9spOPNMKrY95S/7paJ6lF0VH++GBZs4ffOV5iyUL0FO7bh3Zn+dzG3iTv6ut
# HaxNbW3DDV+x3gGe3wXXEMz10/08qg7QePXNxSnDB/Njyqxp2o+7SRrbbq0TSCeZ
# mnE7ZWBZ/C02R7Udmst/bpLqSqydTfiK9eDp5Ou/1dEupyl/5u2rAnViFvxFvdDs
# 0O//FFQwZW2lI2CAD8j2yxo2ggSo8QIDAQABo4IBiTCCAYUwHwYDVR0jBBgwFoAU
# DyrLIIcouOxvSK4rVKYpqhekzQwwHQYDVR0OBBYEFA6KZLOJnjIvjYg1Af3dK1AW
# /LEdMA4GA1UdDwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsG
# AQUFBwMDMEoGA1UdIARDMEEwNQYMKwYBBAGyMQECAQMCMCUwIwYIKwYBBQUHAgEW
# F2h0dHBzOi8vc2VjdGlnby5jb20vQ1BTMAgGBmeBDAEEATBJBgNVHR8EQjBAMD6g
# PKA6hjhodHRwOi8vY3JsLnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2RlU2ln
# bmluZ0NBUjM2LmNybDB5BggrBgEFBQcBAQRtMGswRAYIKwYBBQUHMAKGOGh0dHA6
# Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY0NvZGVTaWduaW5nQ0FSMzYu
# Y3J0MCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTANBgkqhkiG
# 9w0BAQwFAAOCAYEACckUlSqcHqrxDoNkHkURp9r1yhLgcWwnDMvBU69uMqShIJxr
# YszT2fEEs+sfqo4tLyY4/+V6SUIlCj3t22ic7llBXUofcjMAyYogmoRasm1PdG7J
# 35CM4NVXlest4b/N15hgoFYOGqkR4Wh7wH3gXu/4F+z5MeFDQ3n7jFUGIcDpjtRc
# Fdemd/F8yboQ5RibEIM6wYfo8Y/jjw5xSx+bl3EMzdqH3PDxyWIuCub3NNKD+cXH
# z7XqgWKz9Vrxyadwjo5x6SGV6TdeozTwkyoAxdse3RrhzeC5bn+nTJoI/GuSH6FJ
# QpRRrygQeVO4sRJxn++DcOtpoXndT+U5U968ZOHJiwGVzIXfBM99zx5b7dZHOfPF
# 42RCLvctZHDZAXYmiriVlN2a2n6BCO5A2YwSRKXqq3Ygf2cJ8h8s/DSr8Ur2ZjX5
# XLrrpsnWmNilLT+1Q6/bEy9TWXdkauBHq4969N1w9lUGBvOJ8U0jgfv2ZjC53vv6
# dgB37qAjvTLJ5FXRMYIajDCCGogCAQEwaDBUMQswCQYDVQQGEwJHQjEYMBYGA1UE
# ChMPU2VjdGlnbyBMaW1pdGVkMSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBDb2Rl
# IFNpZ25pbmcgQ0EgUjM2AhAQz5q4xih22hjWkHba8NMdMA0GCWCGSAFlAwQCAQUA
# oHwwEAYKKwYBBAGCNwIBDDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPc2
# R74hW4WYij3xw4LwhOlJCeZn8kZgbRNJsO79HQvRMA0GCSqGSIb3DQEBAQUABIIC
# AA/u5WfC4Vxk8hexse80ST0ZBIEk6uHcI13a6nHPKzFaNTJeZEC20dJLJIK6urbB
# 1jPdIRPXePwEVwooa/chiHNnDKwM3eQ8eFRPyofiCIYlYGXExNwPTWVa4f8IRie2
# 0V41aKJsdzDFouXM/rY56zvk0gvdKYosq5+7rBd4OTZIUNSwPcRch94CdUAOtgYU
# F1nXC2ZISL3CT6OHZ/6OwEQZr0k1k0zUWebtvfFGEUU/XVYAOU3XfEp0B2619+MD
# 2oKjIYC8A3V/stSagGcYginkMaxiUFFD0KKEsFlsbnWIcY4BtSUol/yUEKh3TfnN
# If4vu0iq0yEYV3ozwE5JHeTmSATt6o6M6Huf5eRFutUbYOw0wZTqUswlz1xHPCAW
# Aot6EMyKxr7/KodFk/Z3m9VYeGJ8Kvan7AkvNGBjCDDR3ms8Fxen+4wnFTcDP7CX
# aSgw79ZiuRQlYzqtWALgy87/CilPA3cLMlbQtGwuPzzkKbKc2Y0btXsMJHJ3rFlV
# +rt6LcFGWRJ36JjPx4ruWJJPade0qRa880lG0XaR1Eny+brm0G+KUcuZQO9nLGLl
# /Ny0Epp8ab3D4Rc54HaU6gdXgjgds3HlP+P2bXVWHR6SccWCrO5NsCzF4mu7f5h3
# c8Lx0bZPtJPeW/iWBWpxa5ik9ET2FOzi8r3s5LbhIG2KoYIXdzCCF3MGCisGAQQB
# gjcDAwExghdjMIIXXwYJKoZIhvcNAQcCoIIXUDCCF0wCAQMxDzANBglghkgBZQME
# AgEFADB4BgsqhkiG9w0BCRABBKBpBGcwZQIBAQYJYIZIAYb9bAcBMDEwDQYJYIZI
# AWUDBAIBBQAEICxZeARpWQBKpU2J2UxZPrnN8GoNuwfZxPpDDu/HaFqvAhEAqBdH
# 2N5JRkShTcjH4IgVmhgPMjAyNTEwMDcwODUwMDNaoIITOjCCBu0wggTVoAMCAQIC
# EAqA7xhLjfEFgtHEdqeVdGgwDQYJKoZIhvcNAQELBQAwaTELMAkGA1UEBhMCVVMx
# FzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVz
# dGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1IENBMTAeFw0y
# NTA2MDQwMDAwMDBaFw0zNjA5MDMyMzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgU0hBMjU2IFJT
# QTQwOTYgVGltZXN0YW1wIFJlc3BvbmRlciAyMDI1IDEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQDQRqwtEsae0OquYFazK1e6b1H/hnAKAd/KN8wZQjBj
# MqiZ3xTWcfsLwOvRxUwXcGx8AUjni6bz52fGTfr6PHRNv6T7zsf1Y/E3IU8kgNke
# ECqVQ+3bzWYesFtkepErvUSbf+EIYLkrLKd6qJnuzK8Vcn0DvbDMemQFoxQ2Dsw4
# vEjoT1FpS54dNApZfKY61HAldytxNM89PZXUP/5wWWURK+IfxiOg8W9lKMqzdIo7
# VA1R0V3Zp3DjjANwqAf4lEkTlCDQ0/fKJLKLkzGBTpx6EYevvOi7XOc4zyh1uSqg
# r6UnbksIcFJqLbkIXIPbcNmA98Oskkkrvt6lPAw/p4oDSRZreiwB7x9ykrjS6GS3
# NR39iTTFS+ENTqW8m6THuOmHHjQNC3zbJ6nJ6SXiLSvw4Smz8U07hqF+8CTXaETk
# VWz0dVVZw7knh1WZXOLHgDvundrAtuvz0D3T+dYaNcwafsVCGZKUhQPL1naFKBy1
# p6llN3QgshRta6Eq4B40h5avMcpi54wm0i2ePZD5pPIssoszQyF4//3DoK2O65Uc
# k5Wggn8O2klETsJ7u8xEehGifgJYi+6I03UuT1j7FnrqVrOzaQoVJOeeStPeldYR
# NMmSF3voIgMFtNGh86w3ISHNm0IaadCKCkUe2LnwJKa8TIlwCUNVwppwn4D3/Pt5
# pwIDAQABo4IBlTCCAZEwDAYDVR0TAQH/BAIwADAdBgNVHQ4EFgQU5Dv88jHt/f3X
# 85FxYxlQQ89hjOgwHwYDVR0jBBgwFoAU729TSunkBnx6yuKQVvYv1Ensy04wDgYD
# VR0PAQH/BAQDAgeAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMIGVBggrBgEFBQcB
# AQSBiDCBhTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMF0G
# CCsGAQUFBzAChlFodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRU
# cnVzdGVkRzRUaW1lU3RhbXBpbmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5jcnQwXwYD
# VR0fBFgwVjBUoFKgUIZOaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# VHJ1c3RlZEc0VGltZVN0YW1waW5nUlNBNDA5NlNIQTI1NjIwMjVDQTEuY3JsMCAG
# A1UdIAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOC
# AgEAZSqt8RwnBLmuYEHs0QhEnmNAciH45PYiT9s1i6UKtW+FERp8FgXRGQ/YAavX
# zWjZhY+hIfP2JkQ38U+wtJPBVBajYfrbIYG+Dui4I4PCvHpQuPqFgqp1PzC/ZRX4
# pvP/ciZmUnthfAEP1HShTrY+2DE5qjzvZs7JIIgt0GCFD9ktx0LxxtRQ7vllKluH
# WiKk6FxRPyUPxAAYH2Vy1lNM4kzekd8oEARzFAWgeW3az2xejEWLNN4eKGxDJ8WD
# l/FQUSntbjZ80FU3i54tpx5F/0Kr15zW/mJAxZMVBrTE2oi0fcI8VMbtoRAmaasl
# NXdCG1+lqvP4FbrQ6IwSBXkZagHLhFU9HCrG/syTRLLhAezu/3Lr00GrJzPQFnCE
# H1Y58678IgmfORBPC1JKkYaEt2OdDh4GmO0/5cHelAK2/gTlQJINqDr6JfwyYHXS
# d+V08X1JUPvB4ILfJdmL+66Gp3CSBXG6IwXMZUXBhtCyIaehr0XkBoDIGMUG1dUt
# wq1qmcwbdUfcSYCn+OwncVUXf53VJUNOaMWMts0VlRYxe5nK+At+DI96HAlXHAL5
# SlfYxJ7La54i71McVWRP66bW+yERNpbJCjyCYG2j+bdpxo/1Cy4uPcU3AWVPGrbn
# 5PhDBf3Froguzzhk++ami+r3Qrx5bIbY3TVzgiFI7Gq3zWcwgga0MIIEnKADAgEC
# AhANx6xXBf8hmS5AQyIMOkmGMA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVT
# MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
# b20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yNTA1MDcw
# MDAwMDBaFw0zODAxMTQyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5E
# aWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1l
# U3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQC0eDHTCphBcr48RsAcrHXbo0ZodLRRF51NrY0NlLWZ
# loMsVO1DahGPNRcybEKq+RuwOnPhof6pvF4uGjwjqNjfEvUi6wuim5bap+0lgloM
# 2zX4kftn5B1IpYzTqpyFQ/4Bt0mAxAHeHYNnQxqXmRinvuNgxVBdJkf77S2uPoCj
# 7GH8BLuxBG5AvftBdsOECS1UkxBvMgEdgkFiDNYiOTx4OtiFcMSkqTtF2hfQz3zQ
# Sku2Ws3IfDReb6e3mmdglTcaarps0wjUjsZvkgFkriK9tUKJm/s80FiocSk1VYLZ
# lDwFt+cVFBURJg6zMUjZa/zbCclF83bRVFLeGkuAhHiGPMvSGmhgaTzVyhYn4p0+
# 8y9oHRaQT/aofEnS5xLrfxnGpTXiUOeSLsJygoLPp66bkDX1ZlAeSpQl92QOMeRx
# ykvq6gbylsXQskBBBnGy3tW/AMOMCZIVNSaz7BX8VtYGqLt9MmeOreGPRdtBx3yG
# OP+rx3rKWDEJlIqLXvJWnY0v5ydPpOjL6s36czwzsucuoKs7Yk/ehb//Wx+5kMqI
# MRvUBDx6z1ev+7psNOdgJMoiwOrUG2ZdSoQbU2rMkpLiQ6bGRinZbI4OLu9BMIFm
# 1UUl9VnePs6BaaeEWvjJSjNm2qA+sdFUeEY0qVjPKOWug/G6X5uAiynM7Bu2ayBj
# UwIDAQABo4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQU729T
# SunkBnx6yuKQVvYv1Ensy04wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4c
# D08wDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUF
# BwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEG
# CCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRU
# cnVzdGVkUm9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAEGTAX
# MAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBABfO+xaA
# HP4HPRF2cTC9vgvItTSmf83Qh8WIGjB/T8ObXAZz8OjuhUxjaaFdleMM0lBryPTQ
# M2qEJPe36zwbSI/mS83afsl3YTj+IQhQE7jU/kXjjytJgnn0hvrV6hqWGd3rLAUt
# 6vJy9lMDPjTLxLgXf9r5nWMQwr8Myb9rEVKChHyfpzee5kH0F8HABBgr0UdqirZ7
# bowe9Vj2AIMD8liyrukZ2iA/wdG2th9y1IsA0QF8dTXqvcnTmpfeQh35k5zOCPmS
# Nq1UH410ANVko43+Cdmu4y81hjajV/gxdEkMx1NKU4uHQcKfZxAvBAKqMVuqte69
# M9J6A47OvgRaPs+2ykgcGV00TYr2Lr3ty9qIijanrUR3anzEwlvzZiiyfTPjLbnF
# RsjsYg39OlV8cipDoq7+qNNjqFzeGxcytL5TTLL4ZaoBdqbhOhZ3ZRDUphPvSRmM
# Thi0vw9vODRzW6AxnJll38F0cuJG7uEBYTptMSbhdhGQDpOXgpIUsWTjd6xpR6oa
# Qf/DJbg3s6KCLPAlZ66RzIg9sC+NJpud/v4+7RWsWCiKi9EOLLHfMR2ZyJ/+xhCx
# 9yHbxtl5TPau1j/1MIDpMPx0LckTetiSuEtQvLsNz3Qbp7wGWqbIiOWCnb5WqxL3
# /BAPvIXKUjPSxyZsq8WhbaM2tszWkPZPubdcMIIFjTCCBHWgAwIBAgIQDpsYjvnQ
# Lefv21DiCEAYWjANBgkqhkiG9w0BAQwFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UE
# ChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYD
# VQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMjIwODAxMDAwMDAw
# WhcNMzExMTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNl
# cnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdp
# Q2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIK
# AoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Yq3aaza57G4QN
# xDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lXFllVcq9ok3DC
# srp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxeTsiT+CFhmzTr
# BcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbuyntd463JT17l
# Necxy9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I9YI+EJFwq1WC
# QTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmgZ92kJ7yhTzm1
# EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse5w5jrubU75KS
# Op493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKyEbe7f/LVjHAs
# QWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJbOUO
# UlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/Y+whX8QgUWtv
# sauGi0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwIDAQABo4IBOjCC
# ATYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6mK4c
# D08wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDgYDVR0PAQH/BAQD
# AgGGMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGln
# aWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5j
# b20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4oDaG
# NGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RD
# QS5jcmwwEQYDVR0gBAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBwoL9D
# XFXnOF+go3QbPbYW1/e/Vwe9mqyhhyzshV6pGrsi+IcaaVQi7aSId229GhT0E0p6
# Ly23OO/0/4C5+KH38nLeJLxSA8hO0Cre+i1Wz/n096wwepqLsl7Uz9FDRJtDIeuW
# cqFItJnLnU+nBgMTdydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxAGTVGamlUsLih
# Vo7spNU96LHc/RzY9HdaXFSMb++hUD38dglohJ9vytsgjTVgHAIDyyCwrFigDkBj
# xZgiwbJZ9VVrzyerbHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwYw02f
# c7cBqZ9Xql4o4rmUMYIDfDCCA3gCAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUGA1UE
# ChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQg
# VGltZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43xBYLR
# xHanlXRoMA0GCWCGSAFlAwQCAQUAoIHRMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0B
# CRABBDAcBgkqhkiG9w0BCQUxDxcNMjUxMDA3MDg1MDAzWjArBgsqhkiG9w0BCRAC
# DDEcMBowGDAWBBTdYjCshgotMGvaOLFoeVIwB/tBfjAvBgkqhkiG9w0BCQQxIgQg
# AzzDw8Q6x+mKngUzk6Xp8KSEtuxGgBHW0XQbjRJj1ukwNwYLKoZIhvcNAQkQAi8x
# KDAmMCQwIgQgSqA/oizXXITFXJOPgo5na5yuyrM/420mmqM08UYRCjMwDQYJKoZI
# hvcNAQEBBQAEggIAwVkIjKeOqSmR6CmRmFMPi0LObSegBFBvFe9O1JGAVN3XrHky
# YYamRFbSo6YFFafliK4caO9TNynIfxcwdee81v7OMunXHhYMzbvhc7HVHtJ7wITo
# 0YAtF79yK5Wd9z3amGrBMjKNpSt7/f8KBYvZyZbxYJ2AuZCe/t5cgnqmjLsH7HXR
# 8Jp2kmCsw7xwMTC0991olzGpAVo3wW3taE9VGeOaaQeSHTTC7UNxVeMr15eJVHSG
# 34dFMRgPeQ9rIgOuHZFVnlMX5hQG52M7oGM+q4EMV71Dbq8LGXYTneLtA0aaIAyI
# niqU1IVk9SNZSJj8pqD0la6QmRUcqihiBZP/Er5LGyPK5Z7OfJ0uMc0yAUTMMFmr
# CAP17IH+Nz1UFtDr8VP7pTvaurj/Vt3BcT1g6Za+crL5ahlv8WaObRc0W2kvX2gw
# 61zVs62tkqkOe8wDBDJb1j7Tzkeei4hDoh8+tkJzi6chwaKhti4QObtqfUPFGfQp
# Z4UIDPj7JrSqflzN8ux32cgvqg3Md9cK8W+kkGoi4er12byvUv7outH5+EzoLczz
# HXRaFSSAueh7kCqyrWxh+FS8Tm3AhSfp8aj+0ZuoEiQfpG0pptBXjcqD52NuG4lY
# 4y2LqyqOqbuA8JkdOT9oo82bCnEqXfVhXw5eRtor7O1TwC5+EAXqHIith78=
# SIG # End signature block
