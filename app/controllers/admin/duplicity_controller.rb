class Admin::DuplicityController < Admin::Base
  before_filter :is_allowed

  def list
    @virtual_server = VirtualServer.find_by_id(params[:virtual_server_id])
    redirect_to :controller => 'dashboard' and return if !@virtual_server or !@current_user.can_control(@virtual_server)

    @up_level = '/admin/virtual-servers/show?id=' + @virtual_server.id.to_s
    @backups_list = backups_list(@virtual_server)
  end

  def list_data
    virtual_server = VirtualServer.find_by_id(params[:virtual_server_id])
    redirect_to :controller => 'dashboard' and return if !virtual_server or !@current_user.can_control(virtual_server)

    render :json => { :data => backups_list(virtual_server) }
  end

  def delete
    objects_group_operation(Backup, :delete_physically)
  end

  def create
    virtual_server = VirtualServer.find_by_id(params[:virtual_server_id])
    redirect_to :controller => 'dashboard' and return if !virtual_server or !@current_user.can_control(virtual_server)
    hardware_server = virtual_server.hardware_server

    if @current_user.limit_reached?(:limit_backups, virtual_server.backups.count)
      render :json => { :success => false, :message => t('admin.backups.form.create.limit_reached') } and return
    end

    orig_ve_state = virtual_server.state
    ve_state = params[:ve_state]

    if 'running' == orig_ve_state
      case ve_state
        when 'suspend' then virtual_server.suspend
        when 'stop' then virtual_server.stop
      end
    end

    result = Duplicity.backup(virtual_server)
    job_id = result[:job]['job_id']
    backup = result[:backup]
    backup.description = params[:description]

    spawn do
      job = BackgroundJob.create('backups.create', { :identity => virtual_server.identity, :host => hardware_server.host })

      while true
        job_running = false
        job_running = true if hardware_server.rpc_client.job_status(job_id)['alive']
        break unless job_running
        sleep 10
      end

      job.finish

	  # check created file name and size
      name = virtual_server.hardware_server.rpc_client.read_file("/var/lib/vz/dump/#{virtual_server.identity}")
      backup.name = name
      backup.size = virtual_server.hardware_server.rpc_client.exec("du -m /var/lib/vz/dump/#{name}")['output'].to_i


      backup.save
      hardware_server.sync_backups

      if 'running' == orig_ve_state
        case ve_state
          when 'suspend' then virtual_server.resume
          when 'stop' then virtual_server.start
        end
      end
    end

    render :json => { :success => true }
  end

  def restore
#    backup = Backup.find_by_id(params[:id])
    virtual_server = VirtualServer.find_by_id(params[:virtual_server_id])
#    redirect_to :controller => 'dashboard' and return if !virtual_server or !@current_user.can_control(virtual_server)

    orig_ve_state = virtual_server.state
    virtual_server.stop if 'running' == orig_ve_state

	duplicity = Duplicity.new(virtual_server, Time.at(params[:id].to_i), false)
    job_id = duplicity.restore['job_id']

    spawn do
      job = BackgroundJob.create('backups.restore', { :identity => virtual_server.identity, :host => virtual_server.hardware_server.host })

      while true
        job_running = false
        job_running = true if virtual_server.hardware_server.rpc_client.job_status(job_id)['alive']
        break unless job_running
        sleep 10
      end

      job.finish
      virtual_server.start if 'running' == orig_ve_state
    end

    render :json => { :success => true }
  end

  private

    def is_allowed
      if !@current_user.superadmin? && !AppConfig.backups.allow_for_users || !@current_user.can_backup_ve?
        redirect_to :controller => 'admin/dashboard'
      end
    end

    def backups_list(virtual_server)
      backups = Duplicity.all(virtual_server)
      backups.map! { |backup| {
        :id => backup.date.to_i,
        :name => backup.date.to_s,
        :description => backup.full ? "Full backup" : "Incremental backup",
        :size => backup.volumes,
        :archive_date => local_datetime(backup.date),
      }}
    end

end
