Puppet::Type.type(:cgclassify).provide(:cgclassify) do
  desc 'Move running task(s) to given cgroups'

  commands({
    :cgclassify => 'cgclassify',
    :lscgroup   => 'lscgroup',
    :pidof      => 'pidof',
    :ps         => 'ps',
  })

  defaultfor :kernel => :linux
  confine    :kernel => :linux

  def self.instances
    services = Hash.new { |_h, _k| _h[_k] = [] }

    # get custom cgroups
    cgroups = lscgroup.split("\n").reject { |cg| cg.end_with? '/' }

    cgroups.each do |cgname|
      services_in_cgroup = []
      cgroup_path = cgname.delete ':'
      tasks = File.open("#{self.cg_mount_point}/#{cgroup_path}/tasks").read.split("\n")

      tasks.each do |process|
        begin
          # get process name by pid
          services_in_cgroup << ps('-p', process, '-o', 'comm=').chomp
        rescue Puppet::ExecutionFailure => e
          Puppet.debug "[#{__method__}/#{caller[0][/\S+$/]}] #{e}"
          next
        end
      end

      services_in_cgroup.uniq.each do |s|
        services[s] << cgname
      end
    end

    services.collect do |name, cg|
      new(
        :ensure  => :present,
        :name    => name,
        :cgroup  => cg,
      )
    end
  end

  # We iterate over each service entry in the catalog and compare it against
  # the contents of the property_hash generated by self.instances
  def self.prefetch(resources)
    services = instances

    resources.each do |service, resource|
      if provider = services.find { |s| s.name == service }
        resources[service].provider = provider
      end
    end
  end

  mk_resource_methods

  def cgroup=(c_groups)
    cg_opts = []

    cg_remove = @property_hash[:cgroup] - c_groups
    cg_add = c_groups - @property_hash[:cgroup]

    # collect all the changes
    cg_remove.each { |cg| cg_opts << cg[/(\S+):\//] }
    cg_add.each { |cg| cg_opts << cg }

    cgclassify_cmd(cg_opts, @resource[:name]) unless cg_opts.empty?
  end

  def create
    cg_opts = @resource[:cgroup] || []
    cgclassify_cmd(cg_opts, @resource[:name], @resource[:sticky])

    @property_hash[:ensure] = :present
    @property_hash[:cgroup] = @resource[:cgroup]

    exists?
  end

  def destroy
    # set root cgroup for all controllers
    # if it hasn't been defined
    cg_opts = @resource[:cgroup].map { |cg| cg[/(\S+):\//] } rescue ['*:/']
    cgclassify_cmd(cg_opts, @resource[:name])
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def self.cg_mount_point
    '/sys/fs/cgroup'
  end

  private

  def cgclassify_cmd(cgroups, service, sticky = nil)
    self.class.cgclassify_cmd(cgroups, service, sticky)
  end

  def self.cgclassify_cmd(cgroups, service, sticky = nil)
    pidlist = pidof('-x', service).split
    cg_opts = cgroups.map { |cg| ['-g', cg]}.flatten
    cg_opts << sticky if sticky

    cgclassify(cg_opts, pidlist)
  rescue Puppet::ExecutionFailure => e
    Puppet.warning "[#{__method__}/#{caller[0][/\S+$/]}] #{e}"
    false
  end

end