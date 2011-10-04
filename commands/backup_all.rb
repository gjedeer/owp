#
# This script runs a backup on all virtual servers
# Usage:
# ruby script/runner -e production commands/backup_all.rb
#
# Author: GDR!
#

VirtualServer.all.each do |virtual_server|
  hardware_server = virtual_server.hardware_server
  puts "CTID #{virtual_server.identity} on #{hardware_server.host} (#{virtual_server.ip_address})"
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
    print "."
  end
  print "\n"

  job.finish

  # check created file name and size
  name = virtual_server.hardware_server.rpc_client.read_file("/var/lib/vz/dump/#{virtual_server.identity}")
  backup.name = name
  backup.size = virtual_server.hardware_server.rpc_client.exec("du -m /var/lib/vz/dump/#{name}")['output'].to_i

  backup.save
  hardware_server.sync_backups
end # VirtualServer.all
