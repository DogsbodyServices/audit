# Windows Audit Runner - PowerShell Version
# Executes Windows audit on remote Windows servers using PowerShell remoting

$DATE = Get-Date -Format "yyyy-MM-dd"

# Create local directories
New-Item -ItemType Directory -Force -Path "remote_audits" | Out-Null
New-Item -ItemType Directory -Force -Path "screenshots" | Out-Null

Write-Host "Starting Windows audit for multiple hosts..." -ForegroundColor Yellow

# List of Windows servers to audit (update with your server names)
$HOSTS = @(
    "cpa-sql.prod.cloud.local",
    "cpa-vision4.prod.cloud.local"
)

foreach ($targetHost in $HOSTS) {
    Write-Host "`n=====================================" -ForegroundColor Green
    Write-Host "Auditing Windows host: $targetHost" -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    
    # Create host-specific directory
    $hostDir = "remote_audits\$targetHost-$DATE\audit_outputs"
    New-Item -ItemType Directory -Force -Path $hostDir | Out-Null
    
    try {
        # Test connection first
        Write-Host "Testing connection to $targetHost..." -ForegroundColor Yellow
        if (!(Test-NetConnection -ComputerName $targetHost -Port 5985 -InformationLevel Quiet)) {
            Write-Host "ERROR: Cannot connect to $targetHost on port 5985 (WinRM). Skipping..." -ForegroundColor Red
            continue
        }
        
        Write-Host "Connection successful. Running audit on $targetHost..." -ForegroundColor Green
        
        # Execute audit script remotely using PowerShell remoting
        $session = New-PSSession -ComputerName $targetHost -ErrorAction Stop
        
        # Copy the audit script content to remote session and execute
        $auditScriptContent = Get-Content "windows_audit.ps1" -Raw
        
        Invoke-Command -Session $session -ScriptBlock {
            param($scriptContent)
            
            # Execute the audit script
            Invoke-Expression $scriptContent
            
        } -ArgumentList $auditScriptContent
        
        Write-Host "Copying audit results back from $targetHost..." -ForegroundColor Yellow
        
        # Copy results back using PowerShell session
        Copy-Item -FromSession $session -Path "C:\audit_outputs\*" -Destination $hostDir -Recurse -ErrorAction SilentlyContinue
        
        # Clean up remote files
        Write-Host "Cleaning up temporary files on $targetHost..." -ForegroundColor Yellow
        Invoke-Command -Session $session -ScriptBlock {
            Remove-Item -Path "C:\audit_outputs" -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Close session
        Remove-PSSession $session
        
        Write-Host "Audit complete for $targetHost. Files stored in $hostDir" -ForegroundColor Green
        
    } catch {
        Write-Host "ERROR auditing $targetHost : $($_.Exception.Message)" -ForegroundColor Red
        if (Get-Variable session -ErrorAction SilentlyContinue) {
            Remove-PSSession $session -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "`n=====================================" -ForegroundColor Green
Write-Host "All Windows audits complete!" -ForegroundColor Green
Write-Host "Run windows_local_screenshot.ps1 to generate screenshots locally." -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green

# SIG # Begin signature block
# MIIntwYJKoZIhvcNAQcCoIInqDCCJ6QCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA1Iztj+go87jV6
# 8s9R7I66UdxJpCIeVEqGVNg7oEy/4KCCDIIwggYaMIIEAqADAgECAhBiHW0MUgGe
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
# dgB37qAjvTLJ5FXRMYIaizCCGocCAQEwaDBUMQswCQYDVQQGEwJHQjEYMBYGA1UE
# ChMPU2VjdGlnbyBMaW1pdGVkMSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBDb2Rl
# IFNpZ25pbmcgQ0EgUjM2AhAQz5q4xih22hjWkHba8NMdMA0GCWCGSAFlAwQCAQUA
# oHwwEAYKKwYBBAGCNwIBDDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIMBN
# vDLXXy5ODGV4/4YyTIFucVAqSmKJzhx8S7QOu61QMA0GCSqGSIb3DQEBAQUABIIC
# ACXxo7VQ2rEKQghCxAMigAx7ZdwSH25VMzya2YgEcz+Fj6WcvIb54d+L36mEWo6M
# a/wgTn+ms6oGWl49ByCjTMkioa0pBb4CZuNceelXEplSl+oPkrqY8vCT7aC3lSUB
# 4ERF3MAJ1KVz0YU0jIUpKTiySDEWTsrBJVrGaIq11GRmwYkoGVQIY2Kk4yF2tNP7
# XNfHicUZ0CgfaQaWRUmsMUBgvgVCRGR8qBxxXsVF9/6IsxTVqTwWr42IJY45XDSx
# k2P2wHAy49ODJMoQ+Jap561tSdJtfTWcee+jTUXWIQv900L75KP8QDql9kFHkC4w
# YnCKclOuFOhrtOOod/bmCXUC+2ZL6JEQuRsFApbUoh5I1FI5f4wuEdEQ9JErxevz
# hOL42y5sJtocbKcR+o/jSMiTwOR1SDB3DExPHFEYPcbntsgMfderkyRH+qG4YtD6
# Sz831kJRXQKEHSdZO2OgBt52r6MS2Wc0dy6qeyPCI1gRjGR53wR4SiSJILl9yBKd
# XizygzmlbTo+oLzUY9d0QGmUtiO5UTriX5DH8bVL1CJkwasxHwfH98Qgk4kzziN/
# Hj63A2dEVUHOQSN1Ee3aI60kFaPLQc3E1KXuJJGYzKE8gyNCCwEUaXaKldrL92+s
# VOPbDD2ilRC20mzvpEZ2N5Yl0eApZaUOqV9eiOTiBkW2oYIXdjCCF3IGCisGAQQB
# gjcDAwExghdiMIIXXgYJKoZIhvcNAQcCoIIXTzCCF0sCAQMxDzANBglghkgBZQME
# AgEFADB3BgsqhkiG9w0BCRABBKBoBGYwZAIBAQYJYIZIAYb9bAcBMDEwDQYJYIZI
# AWUDBAIBBQAEIPps7v3pq6HWrTFYwuggatvEdCi330fMautK8dCCaGTKAhAQVuLz
# uwx+96Z1ZTVZLGhnGA8yMDI1MTAwNzA4MzY1MFqgghM6MIIG7TCCBNWgAwIBAgIQ
# CoDvGEuN8QWC0cR2p5V0aDANBgkqhkiG9w0BAQsFADBpMQswCQYDVQQGEwJVUzEX
# MBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0
# ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExMB4XDTI1
# MDYwNDAwMDAwMFoXDTM2MDkwMzIzNTk1OVowYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBTSEEyNTYgUlNB
# NDA5NiBUaW1lc3RhbXAgUmVzcG9uZGVyIDIwMjUgMTCCAiIwDQYJKoZIhvcNAQEB
# BQADggIPADCCAgoCggIBANBGrC0Sxp7Q6q5gVrMrV7pvUf+GcAoB38o3zBlCMGMy
# qJnfFNZx+wvA69HFTBdwbHwBSOeLpvPnZ8ZN+vo8dE2/pPvOx/Vj8TchTySA2R4Q
# KpVD7dvNZh6wW2R6kSu9RJt/4QhguSssp3qome7MrxVyfQO9sMx6ZAWjFDYOzDi8
# SOhPUWlLnh00Cll8pjrUcCV3K3E0zz09ldQ//nBZZREr4h/GI6Dxb2UoyrN0ijtU
# DVHRXdmncOOMA3CoB/iUSROUINDT98oksouTMYFOnHoRh6+86Ltc5zjPKHW5KqCv
# pSduSwhwUmotuQhcg9tw2YD3w6ySSSu+3qU8DD+nigNJFmt6LAHvH3KSuNLoZLc1
# Hf2JNMVL4Q1OpbybpMe46YceNA0LfNsnqcnpJeItK/DhKbPxTTuGoX7wJNdoRORV
# bPR1VVnDuSeHVZlc4seAO+6d2sC26/PQPdP51ho1zBp+xUIZkpSFA8vWdoUoHLWn
# qWU3dCCyFG1roSrgHjSHlq8xymLnjCbSLZ49kPmk8iyyizNDIXj//cOgrY7rlRyT
# laCCfw7aSUROwnu7zER6EaJ+AliL7ojTdS5PWPsWeupWs7NpChUk555K096V1hE0
# yZIXe+giAwW00aHzrDchIc2bQhpp0IoKRR7YufAkprxMiXAJQ1XCmnCfgPf8+3mn
# AgMBAAGjggGVMIIBkTAMBgNVHRMBAf8EAjAAMB0GA1UdDgQWBBTkO/zyMe39/dfz
# kXFjGVBDz2GM6DAfBgNVHSMEGDAWgBTvb1NK6eQGfHrK4pBW9i/USezLTjAOBgNV
# HQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwgZUGCCsGAQUFBwEB
# BIGIMIGFMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wXQYI
# KwYBBQUHMAKGUWh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRy
# dXN0ZWRHNFRpbWVTdGFtcGluZ1JTQTQwOTZTSEEyNTYyMDI1Q0ExLmNydDBfBgNV
# HR8EWDBWMFSgUqBQhk5odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRU
# cnVzdGVkRzRUaW1lU3RhbXBpbmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5jcmwwIAYD
# VR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4IC
# AQBlKq3xHCcEua5gQezRCESeY0ByIfjk9iJP2zWLpQq1b4URGnwWBdEZD9gBq9fN
# aNmFj6Eh8/YmRDfxT7C0k8FUFqNh+tshgb4O6Lgjg8K8elC4+oWCqnU/ML9lFfim
# 8/9yJmZSe2F8AQ/UdKFOtj7YMTmqPO9mzskgiC3QYIUP2S3HQvHG1FDu+WUqW4da
# IqToXFE/JQ/EABgfZXLWU0ziTN6R3ygQBHMUBaB5bdrPbF6MRYs03h4obEMnxYOX
# 8VBRKe1uNnzQVTeLni2nHkX/QqvXnNb+YkDFkxUGtMTaiLR9wjxUxu2hECZpqyU1
# d0IbX6Wq8/gVutDojBIFeRlqAcuEVT0cKsb+zJNEsuEB7O7/cuvTQasnM9AWcIQf
# VjnzrvwiCZ85EE8LUkqRhoS3Y50OHgaY7T/lwd6UArb+BOVAkg2oOvol/DJgddJ3
# 5XTxfUlQ+8Hggt8l2Yv7roancJIFcbojBcxlRcGG0LIhp6GvReQGgMgYxQbV1S3C
# rWqZzBt1R9xJgKf47CdxVRd/ndUlQ05oxYy2zRWVFjF7mcr4C34Mj3ocCVccAvlK
# V9jEnstrniLvUxxVZE/rptb7IRE2lskKPIJgbaP5t2nGj/ULLi49xTcBZU8atufk
# +EMF/cWuiC7POGT75qaL6vdCvHlshtjdNXOCIUjsarfNZzCCBrQwggScoAMCAQIC
# EA3HrFcF/yGZLkBDIgw6SYYwDQYJKoZIhvcNAQELBQAwYjELMAkGA1UEBhMCVVMx
# FTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNv
# bTEhMB8GA1UEAxMYRGlnaUNlcnQgVHJ1c3RlZCBSb290IEc0MB4XDTI1MDUwNzAw
# MDAwMFoXDTM4MDExNDIzNTk1OVowaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRp
# Z2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVT
# dGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1IENBMTCCAiIwDQYJKoZIhvcNAQEB
# BQADggIPADCCAgoCggIBALR4MdMKmEFyvjxGwBysddujRmh0tFEXnU2tjQ2UtZmW
# gyxU7UNqEY81FzJsQqr5G7A6c+Gh/qm8Xi4aPCOo2N8S9SLrC6Kbltqn7SWCWgzb
# NfiR+2fkHUiljNOqnIVD/gG3SYDEAd4dg2dDGpeZGKe+42DFUF0mR/vtLa4+gKPs
# YfwEu7EEbkC9+0F2w4QJLVSTEG8yAR2CQWIM1iI5PHg62IVwxKSpO0XaF9DPfNBK
# S7Zazch8NF5vp7eaZ2CVNxpqumzTCNSOxm+SAWSuIr21Qomb+zzQWKhxKTVVgtmU
# PAW35xUUFREmDrMxSNlr/NsJyUXzdtFUUt4aS4CEeIY8y9IaaGBpPNXKFifinT7z
# L2gdFpBP9qh8SdLnEut/GcalNeJQ55IuwnKCgs+nrpuQNfVmUB5KlCX3ZA4x5HHK
# S+rqBvKWxdCyQEEGcbLe1b8Aw4wJkhU1JrPsFfxW1gaou30yZ46t4Y9F20HHfIY4
# /6vHespYMQmUiote8ladjS/nJ0+k6MvqzfpzPDOy5y6gqztiT96Fv/9bH7mQyogx
# G9QEPHrPV6/7umw052AkyiLA6tQbZl1KhBtTasySkuJDpsZGKdlsjg4u70EwgWbV
# RSX1Wd4+zoFpp4Ra+MlKM2baoD6x0VR4RjSpWM8o5a6D8bpfm4CLKczsG7ZrIGNT
# AgMBAAGjggFdMIIBWTASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1UdDgQWBBTvb1NK
# 6eQGfHrK4pBW9i/USezLTjAfBgNVHSMEGDAWgBTs1+OC0nFdZEzfLmc/57qYrhwP
# TzAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwgwdwYIKwYBBQUH
# AQEEazBpMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQQYI
# KwYBBQUHMAKGNWh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRy
# dXN0ZWRSb290RzQuY3J0MEMGA1UdHwQ8MDowOKA2oDSGMmh0dHA6Ly9jcmwzLmRp
# Z2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRSb290RzQuY3JsMCAGA1UdIAQZMBcw
# CAYGZ4EMAQQCMAsGCWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAF877FoAc
# /gc9EXZxML2+C8i1NKZ/zdCHxYgaMH9Pw5tcBnPw6O6FTGNpoV2V4wzSUGvI9NAz
# aoQk97frPBtIj+ZLzdp+yXdhOP4hCFATuNT+ReOPK0mCefSG+tXqGpYZ3essBS3q
# 8nL2UwM+NMvEuBd/2vmdYxDCvwzJv2sRUoKEfJ+nN57mQfQXwcAEGCvRR2qKtntu
# jB71WPYAgwPyWLKu6RnaID/B0ba2H3LUiwDRAXx1Neq9ydOal95CHfmTnM4I+ZI2
# rVQfjXQA1WSjjf4J2a7jLzWGNqNX+DF0SQzHU0pTi4dBwp9nEC8EAqoxW6q17r0z
# 0noDjs6+BFo+z7bKSBwZXTRNivYuve3L2oiKNqetRHdqfMTCW/NmKLJ9M+MtucVG
# yOxiDf06VXxyKkOirv6o02OoXN4bFzK0vlNMsvhlqgF2puE6FndlENSmE+9JGYxO
# GLS/D284NHNboDGcmWXfwXRy4kbu4QFhOm0xJuF2EZAOk5eCkhSxZON3rGlHqhpB
# /8MluDezooIs8CVnrpHMiD2wL40mm53+/j7tFaxYKIqL0Q4ssd8xHZnIn/7GELH3
# IdvG2XlM9q7WP/UwgOkw/HQtyRN62JK4S1C8uw3PdBunvAZapsiI5YKdvlarEvf8
# EA+8hcpSM9LHJmyrxaFtoza2zNaQ9k+5t1wwggWNMIIEdaADAgECAhAOmxiO+dAt
# 5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNV
# BAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEwMDAwMDBa
# Fw0zMTExMDkyMzU5NTlaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lD
# ZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
# ggIBAL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3E
# MB/zG6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKy
# unWZanMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsF
# xl7sWxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU1
# 5zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJB
# MtfbBHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObUR
# WBf3JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6
# nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxB
# YKqxYxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5S
# UUd0viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+x
# q4aLT8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjggE6MIIB
# NjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/57qYrhwP
# TzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzAOBgNVHQ8BAf8EBAMC
# AYYweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdp
# Y2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNv
# bS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0
# aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENB
# LmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcNAQEMBQADggEBAHCgv0Nc
# Vec4X6CjdBs9thbX979XB72arKGHLOyFXqkauyL4hxppVCLtpIh3bb0aFPQTSnov
# Lbc47/T/gLn4offyct4kvFIDyE7QKt76LVbP+fT3rDB6mouyXtTP0UNEm0Mh65Zy
# oUi0mcudT6cGAxN3J0TU53/oWajwvy8LpunyNDzs9wPHh6jSTEAZNUZqaVSwuKFW
# juyk1T3osdz9HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPF
# mCLBsln1VWvPJ6tsds5vIy30fnFqI2si/xK4VC0nftg62fC2h5b9W9FcrBjDTZ9z
# twGpn1eqXijiuZQxggN8MIIDeAIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQK
# Ew5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBU
# aW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEFgtHE
# dqeVdGgwDQYJYIZIAWUDBAIBBQCggdEwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJ
# EAEEMBwGCSqGSIb3DQEJBTEPFw0yNTEwMDcwODM2NTBaMCsGCyqGSIb3DQEJEAIM
# MRwwGjAYMBYEFN1iMKyGCi0wa9o4sWh5UjAH+0F+MC8GCSqGSIb3DQEJBDEiBCCI
# rct7DeKah4bUUYH3SrRz9PuDMRBaY4uFXtCOptfyFjA3BgsqhkiG9w0BCRACLzEo
# MCYwJDAiBCBKoD+iLNdchMVck4+CjmdrnK7Ksz/jbSaaozTxRhEKMzANBgkqhkiG
# 9w0BAQEFAASCAgC1OD6uaPDQBTAaBcuHzl5syhk1J+PruQ9t4DsKjz5R6CLZHCju
# rl3GsxeHTVz9mxrb9N+c6Pu56/8hP94Af/BweTJN2lOW8TkcVoWXlxOVGHPZTchy
# TLkI7cTH6r4oThoQlwxY8D7pv5fj56iiVfJnrB/a65NgqveraomLbwTT+rK1EH5e
# sSVRTPAToS8cY3BdQQdi4UkqDvQJHYFjaCqh6cCSqSqqRvMVBjTpYUrL2qDm7u13
# mWZMIAFrUayVhW1xEEsAgjzYJ/652EgYU4ttc0CT4oyfojcqVfaVQ0C6ynWK9Ifn
# IkDluSbQC1LzG84dco7RYXvtWI5vSu6TXF9NoO95Lb2LSf+b/34AFMNpJiFx10wA
# EWokZbYPceE2BsfJnMRJ09gzGoj5f1A+Izpn3taY7q6wJ7TZ8vvrln7s6wsnqTH3
# Gr7X1fV7hQIg/Q6mMGWL8IachpmbEyLAUBrtbb+D8dKXBKmZgGR1QzpqcNE9BVMn
# sY6gjQEHXW9fSKviI1+upYQkvlt3wWhyyeKxbPFFX5Ubq53H9pkccqyt7wkBUSyL
# Ie57pgI+ZhxoEFTY6aUsoOP4FrFkIfDM0blMDyDmkutZdmzEM7/YaiH0o1Bb9YOL
# K+zS5YZP8BRzEpa076GjbUWItRytX5CPjXa4r92UJ1XBgW+3uA0eW7x7dA==
# SIG # End signature block
