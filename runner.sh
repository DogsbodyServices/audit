#!/bin/bash

# Create local directories for each host
mkdir -p remote_audits screenshots

for host in 10duke-app3.stage.cloud.local 10duke-app4.stage.cloud.local; do
  echo "Auditing $host..."
  
  # Create host-specific directory
  mkdir -p "remote_audits/$host/audit_outputs"
  
  # Run the audit script remotely (without screenshots)
  ssh aaron.watson@$host 'bash -s' < linux_audit_remote.sh
  
  # Copy the audit outputs back to local machine
  scp -r aaron.watson@$host:~/audit_outputs/* "remote_audits/$host/audit_outputs/"
  
  # Clean up remote files
  ssh aaron.watson@$host 'rm -rf audit_outputs screenshots'
  
  echo "Audit complete for $host. Files stored in remote_audits/$host/"
done

echo "All remote audits complete. Run local_screenshot.sh to generate screenshots locally."