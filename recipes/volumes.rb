node[:ebs][:volumes].each do |mount_point, options|

  # skip volumes that already exist
  next if File.read('/etc/mtab').split("\n").any?{|line| line.match(" #{mount_point} ")}

  # create ebs volume
  if !options[:device]
    if node[:ebs][:creds][:encrypted]
      credentials = Chef::EncryptedDataBagItem.load(node[:ebs][:creds][:databag], node[:ebs][:creds][:item])
    else
      if !node[:ebs][:creds][:iam_roles]
        credentials = data_bag_item node[:ebs][:creds][:databag], node[:ebs][:creds][:item]
      end
    end

    devices = Dir.glob('/dev/xvd?')
    devices = ['/dev/xvdf'] if devices.empty?
    devid = devices.sort.last[-1,1].succ
    devid = 'f' unless devid >= 'f'
    device = "/dev/sd#{devid}"
  else
    devices = ["#{options[:device]}"]
    devid = devices.sort.last[-1,1]
  end

  device = "/dev/sd#{devid}"

  if options[:size]
    vol = aws_ebs_volume device do
      if !node[:ebs][:creds][:iam_roles]
        aws_access_key credentials[node.ebs.creds.aki]
        aws_secret_access_key credentials[node.ebs.creds.sak]
      end
      size options[:size]
      device device
      availability_zone node[:ec2][:placement_availability_zone]
      volume_type options[:piops] ? 'io1' : options[:gp2] ? 'gp2' : 'standard'
      piops options[:piops]
      if node[:ebs][:volume][:encryption]
        encrypted  true
        kms_key_id node[:ebs][:volume][:kms_key_id]
      end
      action :nothing
      delete_on_termination options[:delete_on_termination]
    end
    vol.run_action(:create)
    vol.run_action(:attach)
    node.set[:ebs][:volumes][mount_point][:device] = "/dev/xvd#{devid}"
    node.save unless Chef::Config[:solo]
  end

  # mount volume

  # Use the provided device name, or the name of the mounted device if a device was not provided
  device = options[:device] || node[:ebs][:volumes][mount_point][:device]

  execute 'mkfs' do
    only_if { device and options.has_key?(:fstype) }
    command "mkfs -t #{options[:fstype]} #{device}"
    not_if do
      BlockDevice.wait_for(device)
      system("blkid -s TYPE -o value #{device}")
    end
  end

  directory mount_point do
    recursive true
    action :create
    mode 0755
  end

  mount mount_point do
    fstype options[:fstype]
    device device
    options 'noatime,nobootwait'
    action [:mount, :enable]
  end

end
