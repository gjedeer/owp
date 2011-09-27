class Backup < ActiveRecord::Base
  belongs_to :virtual_server

  def date
    match = name.match(/^ve-dump\.(\d+)\.(\d+)\.tar$/)
	if match.nil?
		match = name.match(/^vzdump-openvz-(\d+)-(\d{4})_(\d+)_(\d+)-(\d+)_(\d+)_(\d+)\.tgz$/)
		if match.nil?
           	name
		else
			Time.local(match[2], match[3],  match[4],  match[5],  match[6],  match[7])  
		end
	else
	    Time.at(match[2].to_i)
	end
  end

  def delete_physically
    hardware_server = virtual_server.hardware_server

    hardware_server.rpc_client.exec("rm #{hardware_server.backups_dir}/#{self.name}")
    destroy
  end

  def self.backup(virtual_server)
    veid = virtual_server.identity
    job = virtual_server.hardware_server.rpc_client.job('vzdump', "--compress --snapshot --script /root/bin/vzdump-hook.py #{veid}")

	retries = 0

    server_backup = Backup.new(:name => 'unknown', :virtual_server_id => virtual_server.id)
    { :job => job, :backup => server_backup }
  end

  def restore
    virtual_server.hardware_server.rpc_client.exec('rm', "-rf #{virtual_server.private_dir}") if virtual_server.private_dir.length > 1
    backup_name = "#{virtual_server.hardware_server.backups_dir}/#{name}"
    virtual_server.hardware_server.rpc_client.job('tar', "-xf #{backup_name} -C /")
  end

end
