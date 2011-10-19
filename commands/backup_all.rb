#
# This script runs a backup on all virtual servers
# Usage:
# ruby script/runner -e production commands/backup_all.rb
#
# Author: GDR!
#

log = File.open('/var/log/vzbackup', 'a')

log.write(Time.now.to_s + " Starting backup of #{VirtualServer.all.count} virtual machines\n")
log.flush

VirtualServer.all.each do |virtual_server|
  hardware_server = virtual_server.hardware_server
  log.write(Time.now.to_s + " CTID #{virtual_server.identity} on #{hardware_server.host} (#{virtual_server.ip_address})\n")
  log.flush
  result = virtual_server.backup
  job_id = result[:job]['job_id']
  backup = result[:backup]
  backup.description = "Backup performed automatically"

  job = BackgroundJob.create('backups.create', { :identity => virtual_server.identity, :host => hardware_server.host })

  while true
    job_running = false
    job_running = true if hardware_server.rpc_client.job_status(job_id)['alive']
    break unless job_running
    sleep 10
    log.write(Time.now.to_s + " waiting\n")
    log.flush
  end

  job.finish
  log.write(Time.now.to_s + " Finished backing up CTID #{virtual_server.identity} on #{hardware_server.host}\n")
  log.flush

  # check created file name and size
  name = virtual_server.hardware_server.rpc_client.read_file("/var/lib/vz/dump/#{virtual_server.identity}")
  backup.name = name
  backup.size = virtual_server.hardware_server.rpc_client.exec("du -m /var/lib/vz/dump/#{name}")['output'].to_i

  backup.save
  hardware_server.sync_backups
end # VirtualServer.all

log.close
