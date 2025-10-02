#!/bin/bash

# Local screenshot script to generate screenshots from collected audit data
mkdir -p screenshots

function screenshot_file() {
    local file_path="$1"
    local screenshot_name="$2"
    local description="$3"
    
    if [ -f "$file_path" ]; then
        echo "Taking screenshot of $description..."
        
        # Open file in gedit for screenshot
        gedit "$file_path" &
        GEDIT_PID=$!
        
        # Wait for gedit to open
        sleep 3
        
        # Take screenshot
        gnome-screenshot -f "screenshots/$screenshot_name"
        
        # Close gedit
        kill $GEDIT_PID 2>/dev/null
        sleep 1
        
        echo "Screenshot saved: screenshots/$screenshot_name"
    else
        echo "File not found: $file_path"
    fi
}

# Process each host's audit results
for host_dir in remote_audits/*/; do
    if [ -d "$host_dir" ]; then
        host=$(basename "$host_dir")
        echo "Processing screenshots for $host..."
        
        mkdir -p "screenshots/$host"
        
        # Screenshot each audit file
        screenshot_file "$host_dir/audit_outputs/etc_shadow.txt" "$host/etc_shadow.png" "$host /etc/shadow file"
        screenshot_file "$host_dir/audit_outputs/login_defs.txt" "$host/login_defs.png" "$host /etc/login.defs file"
        screenshot_file "$host_dir/audit_outputs/pam_system_auth.txt" "$host/pam_system_auth.png" "$host PAM system-auth file"
        screenshot_file "$host_dir/audit_outputs/hosts_equiv.txt" "$host/hosts_equiv.png" "$host /etc/hosts.equiv file"
        screenshot_file "$host_dir/audit_outputs/passwd.txt" "$host/passwd.png" "$host /etc/passwd file"
        screenshot_file "$host_dir/audit_outputs/group.txt" "$host/group.png" "$host /etc/group file"
        screenshot_file "$host_dir/audit_outputs/sulog.txt" "$host/sulog.png" "$host /var/adm/sulog file"
        screenshot_file "$host_dir/audit_outputs/sudoers.txt" "$host/sudoers.png" "$host /etc/sudoers file"
        screenshot_file "$host_dir/audit_outputs/securetty.txt" "$host/securetty.png" "$host /etc/securetty file"
        screenshot_file "$host_dir/audit_outputs/pam_login.txt" "$host/pam_login.png" "$host PAM login file"
        screenshot_file "$host_dir/audit_outputs/patch_list.txt" "$host/patch_list.png" "$host Installed patches"
        
        # Screenshot permission files
        for perm_file in "$host_dir"/audit_outputs/perm_*.txt; do
            if [ -f "$perm_file" ]; then
                filename=$(basename "$perm_file" .txt)
                screenshot_file "$perm_file" "$host/$filename.png" "$host $filename"
            fi
        done
        
        echo "Screenshots complete for $host"
    fi
done

echo "All screenshots generated in screenshots/ directory"
