for host in 10duke-app3.stage.cloud.local 10duke-app4.stage.cloud.local; do
  ssh $host 'bash -s' < linux_audit.sh
  # Or use Ansible's `delegate_to` and `inventory_hostname`
done