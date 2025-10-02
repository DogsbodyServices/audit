#!/bin/bash

# Get current date for timestamping
DATE=$(date +%Y-%m-%d)

# Create local directories for each host
mkdir -p remote_audits screenshots

for host in cpa-app14.prod.cloud.local cpa-auth-proxy.prod.cloud.local mwf-mgroup.prod.cloud.local mwf-mgroup2.prod.cloud.local; do
  echo "Auditing $host..."
  
  # Create host-specific directory with date
  mkdir -p "remote_audits/$host-$DATE/audit_outputs"
  
  # Pass the date to the remote script and run it
  ssh aaron.watson@$host -o StrictHostKeyChecking=accept-new "DATE=$DATE bash -s" < linux_audit_remote.sh
  
  # Copy the audit outputs back to local machine
  scp -r aaron.watson@$host:~/audit_outputs/* "remote_audits/$host-$DATE/audit_outputs/"
  
  # Clean up remote files
  ssh aaron.watson@$host 'rm -rf audit_outputs screenshots'
  
  echo "Audit complete for $host. Files stored in remote_audits/$host-$DATE/"
done

echo "All remote audits complete. Run local_screenshot.sh to generate screenshots locally."