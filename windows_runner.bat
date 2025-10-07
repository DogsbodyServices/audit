@echo off
REM Windows Audit Runner Script
REM Executes Windows audit on remote Windows servers

set DATE=%date:~-4,4%-%date:~-7,2%-%date:~-10,2%

REM Create local directories
if not exist "remote_audits" mkdir remote_audits
if not exist "screenshots" mkdir screenshots

echo Starting Windows audit for multiple hosts...

REM List of Windows servers to audit
set HOSTS=server1.domain.local server2.domain.local

for %%h in (%HOSTS%) do (
    echo.
    echo =====================================
    echo Auditing Windows host: %%h
    echo =====================================
    
    REM Create host-specific directory
    mkdir "remote_audits\%%h-%DATE%\audit_outputs" 2>nul
    
    REM Copy PowerShell script to remote host and execute
    echo Copying audit script to %%h...
    copy windows_audit.ps1 "\\%%h\c$\temp\windows_audit.ps1" >nul 2>&1
    
    if errorlevel 1 (
        echo ERROR: Could not copy script to %%h. Check network connectivity and permissions.
        continue
    )
    
    echo Running audit on %%h...
    REM Execute PowerShell script remotely
    psexec \\%%h -s powershell.exe -ExecutionPolicy Bypass -File "C:\temp\windows_audit.ps1"
    
    if errorlevel 1 (
        echo WARNING: Audit may have completed with errors on %%h
    )
    
    echo Copying audit results back from %%h...
    REM Copy results back to local machine
    xcopy "\\%%h\c$\audit_outputs\*" "remote_audits\%%h-%DATE%\audit_outputs\" /Y /Q >nul 2>&1
    
    if errorlevel 1 (
        echo ERROR: Could not copy results from %%h
    ) else (
        echo Successfully copied results from %%h
    )
    
    REM Clean up remote files
    echo Cleaning up temporary files on %%h...
    del "\\%%h\c$\temp\windows_audit.ps1" >nul 2>&1
    rmdir /S /Q "\\%%h\c$\audit_outputs" >nul 2>&1
    
    echo Audit complete for %%h. Files stored in remote_audits\%%h-%DATE%\
)

echo.
echo =====================================
echo All Windows audits complete!
echo Run windows_local_screenshot.bat to generate screenshots locally.
echo =====================================
pause
