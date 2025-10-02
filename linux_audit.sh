#!/bin/bash

# Directory setup
mkdir -p audit_outputs screenshots

# Function to redact shadow file passwords
function redact_shadow_passwords() {
    local input_file="$1"
    local output_file="$2"
    
    # Read shadow file and replace password hashes with [REDACTED]
    sudo cat "$input_file" | sed 's/:[^:]*:/:***REDACTED***:/2' > "$output_file"
}

# Function to run command, save output, open for screenshot, and take screenshot
function audit_and_screenshot() {
    local cmd="$1"
    local output_file="$2"
    local screenshot_file="$3"
    local description="$4"

    echo "==== $description ====" | tee "$output_file"
    eval "$cmd" | tee -a "$output_file"
    # Optional: open output in gedit for easier reading
    # gedit "$output_file" &
    # sleep 2  # Give time for gedit to open

    # Take full desktop screenshot (includes clock)
    gnome-screenshot -f "$screenshot_file"
    # pkill gedit  # Close gedit if used
    sleep 1
}

# Special function for shadow file with redaction
function audit_and_screenshot_shadow() {
    local input_file="$1"
    local output_file="$2"
    local screenshot_file="$3"
    local description="$4"

    echo "==== $description ====" | tee "$output_file"
    redact_shadow_passwords "$input_file" "/tmp/shadow_redacted"
    cat "/tmp/shadow_redacted" | tee -a "$output_file"
    rm -f "/tmp/shadow_redacted"
    
    # Take full desktop screenshot (includes clock)
    gnome-screenshot -f "$screenshot_file"
    sleep 1
}

# 1. /etc/shadow (with password redaction)
audit_and_screenshot_shadow "/etc/shadow" "audit_outputs/etc_shadow.txt" "screenshots/etc_shadow.png" "/etc/shadow file (passwords redacted)"

# 2. /etc/login.defs
audit_and_screenshot "sudo cat /etc/login.defs" "audit_outputs/login_defs.txt" "screenshots/login_defs.png" "/etc/login.defs file"

# 3. PAM config
audit_and_screenshot "sudo cat /etc/pam.d/system-auth" "audit_outputs/pam_system_auth.txt" "screenshots/pam_system_auth.png" "PAM system-auth file"

# 4. /etc/hosts.equiv
audit_and_screenshot "sudo cat /etc/hosts.equiv" "audit_outputs/hosts_equiv.txt" "screenshots/hosts_equiv.png" "/etc/hosts.equiv file"

# 5. /etc/passwd
audit_and_screenshot "sudo cat /etc/passwd" "audit_outputs/passwd.txt" "screenshots/passwd.png" "/etc/passwd file"

# 6. /etc/group
audit_and_screenshot "sudo cat /etc/group" "audit_outputs/group.txt" "screenshots/group.png" "/etc/group file"

# 7. /var/adm/sulog
audit_and_screenshot "sudo cat /var/adm/sulog" "audit_outputs/sulog.txt" "screenshots/sulog.png" "/var/adm/sulog file"

# 8. /etc/sudoers
audit_and_screenshot "sudo cat /etc/sudoers" "audit_outputs/sudoers.txt" "screenshots/sudoers.png" "/etc/sudoers file"

# 9. File permissions for key files
for file in /etc/exports /etc/inetd.conf /etc/passwd /etc/services /etc/shadow /etc/securetty /etc/group /etc/ftpusers; do
    [ -e "$file" ] && audit_and_screenshot "ls -l $file" "audit_outputs/perm_$(basename $file).txt" "screenshots/perm_$(basename $file).png" "Permissions of $file"
done

# 10. /etc/securetty
audit_and_screenshot "sudo cat /etc/securetty" "audit_outputs/securetty.txt" "screenshots/securetty.png" "/etc/securetty file"

# 11. /etc/pam.d/login
audit_and_screenshot "sudo cat /etc/pam.d/login" "audit_outputs/pam_login.txt" "screenshots/pam_login.png" "PAM login file"

# 12. Patch list
audit_and_screenshot "rpm -qai" "audit_outputs/patch_list.txt" "screenshots/patch_list.png" "Installed patches (rpm -qai)"

echo "Audit complete. Outputs and screenshots are stored in audit_outputs/ and screenshots/"