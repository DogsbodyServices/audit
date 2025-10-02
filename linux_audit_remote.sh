#!/bin/bash

# Get date for timestamping (will be passed from runner or set locally)
if [ -z "$DATE" ]; then
    DATE=$(date +%Y-%m-%d)
fi

# Directory setup
mkdir -p audit_outputs

# Function to redact shadow file passwords
function redact_shadow_passwords() {
    local input_file="$1"
    local output_file="$2"
    
    # Read shadow file and replace password hashes with [REDACTED]
    # Format: username:password:lastchange:min:max:warn:inactive:expire:reserved
    sudo cat "$input_file" | sed 's/\([^:]*\):\([^:]*\):/\1:***REDACTED***:/' > "$output_file"
}

# Function to run command and save output (no screenshots for remote execution)
function audit_only() {
    local cmd="$1"
    local output_file="$2"
    local description="$3"

    echo "==== $description ====" | tee "$output_file"
    eval "$cmd" | tee -a "$output_file"
    echo "Completed: $description"
}

# Special function for shadow file with redaction (no screenshots)
function audit_shadow_only() {
    local input_file="$1"
    local output_file="$2"
    local description="$3"

    echo "==== $description ====" | tee "$output_file"
    redact_shadow_passwords "$input_file" "/tmp/shadow_redacted"
    cat "/tmp/shadow_redacted" | tee -a "$output_file"
    rm -f "/tmp/shadow_redacted"
    echo "Completed: $description"
}

# 1. /etc/shadow (with password redaction)
audit_shadow_only "/etc/shadow" "audit_outputs/etc_shadow_$DATE.txt" "/etc/shadow file (passwords redacted)"

# 2. /etc/login.defs
audit_only "sudo cat /etc/login.defs" "audit_outputs/login_defs_$DATE.txt" "/etc/login.defs file"

# 3. PAM config
audit_only "sudo cat /etc/pam.d/system-auth" "audit_outputs/pam_system_auth_$DATE.txt" "PAM system-auth file"

# 4. /etc/hosts.equiv
audit_only "sudo cat /etc/hosts.equiv" "audit_outputs/hosts_equiv_$DATE.txt" "/etc/hosts.equiv file"

# 5. /etc/passwd
audit_only "sudo cat /etc/passwd" "audit_outputs/passwd_$DATE.txt" "/etc/passwd file"

# 6. /etc/group
audit_only "sudo cat /etc/group" "audit_outputs/group_$DATE.txt" "/etc/group file"

# 7. /var/adm/sulog
audit_only "sudo cat /var/adm/sulog" "audit_outputs/sulog_$DATE.txt" "/var/adm/sulog file"

# 8. /etc/sudoers
audit_only "sudo cat /etc/sudoers" "audit_outputs/sudoers_$DATE.txt" "/etc/sudoers file"

# 9. File permissions for key files
for file in /etc/exports /etc/inetd.conf /etc/passwd /etc/services /etc/shadow /etc/securetty /etc/group /etc/ftpusers; do
    [ -e "$file" ] && audit_only "ls -l $file" "audit_outputs/perm_$(basename $file)_$DATE.txt" "Permissions of $file"
done

# 10. /etc/securetty
audit_only "sudo cat /etc/securetty" "audit_outputs/securetty_$DATE.txt" "/etc/securetty file"

# 11. /etc/pam.d/login
audit_only "sudo cat /etc/pam.d/login" "audit_outputs/pam_login_$DATE.txt" "PAM login file"

# 12. Patch list
audit_only "rpm -qai" "audit_outputs/patch_list_$DATE.txt" "Installed patches (rpm -qai)"

echo "Remote audit complete. Outputs stored in audit_outputs/"
