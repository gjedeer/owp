class Duplicity
  attr_accessor :virtual_server, :date, :full, :volumes

  def self.all(virtual_server)
	duplicity_destination="scp://gdr@192.168.1.3/tmp/dup"
    hardware_server = virtual_server.hardware_server

    result = `duplicity collection-status --no-encryption #{duplicity_destination}/#{hardware_server.host}/#{virtual_server.identity}`
#    print result
	
	backups = []

	result.each_line do |line|
		match = /\s+([A-Z][a-z]+)\s+([A-Z][a-z]+)\s+([A-Z][a-z]+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d+)\s+(\d+)/.match(line)
		if match
			full = false
			if match[1] == 'Full'
				full = true
			end

			date = Time.local(match[8], match[3], match[4], match[5], match[6], match[7])

			backup = Duplicity.new(virtual_server, date, full)
            backup.volumes = match[9]

			backups.unshift(backup)
		end
	end

	backups
  end

  def initialize(virtual_server, date, full)
	  @virtual_server = virtual_server
	  @date = date
	  @full = full
  end


  def self.backup(virtual_server)
    veid = virtual_server.identity
    job = virtual_server.hardware_server.rpc_client.job('/root/bin/vzdup', "#{veid}")

	retries = 0

    server_backup = Backup.new(:name => 'unknown', :virtual_server_id => virtual_server.id)
    { :job => job, :backup => server_backup }
  end

  def restore
    mylog = Logger.new("#{Rails.root}/log/my.log")
	mylog.info('Ojajebie!' + @date.to_s + @virtual_server.id.to_s)
    virtual_server.hardware_server.rpc_client.job('/root/vzdup/vzduprestore', "--force #{@date.iso8601(0)} #{@virtual_server.identity}")
  end

end
