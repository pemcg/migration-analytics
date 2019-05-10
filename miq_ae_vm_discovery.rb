#
# This method collects useful data that is relevant to the VM migration, for one or more VMs 
#
# Inputs: $evm.object['return_format'],   options: 'yaml', 'json', 'json_pretty'
#         $evm.object['output'],          options: 'log', 'file://filename', 'options_hash'
#
#
module ManageIQ
  module Automate
    module Transformation
      module Analytics
        module Methods
          class VMDiscovery
            require 'rbvmomi'
            require 'yaml'

            OUTPUT_DIRECTORY = "/tmp/migration_analytics".freeze

            def initialize(handle = $evm)
              @handle = handle
            end

            def recursive_find_vm(folder, name, exact = false)
              found = []
              folder.children.each do |child|
                if matches(child, name, exact)
                  found << child
                elsif child.class == RbVmomi::VIM::Folder
                  found << recursive_find_vm(child, name, exact)
                end
              end
              found.flatten
            end

            def matches(child, name, exact = false)
              is_vm = child.class == RbVmomi::VIM::VirtualMachine
              name_matches = (name == "*") || (exact ? (child.name == name) : (child.name.include? name))
              return is_vm && name_matches
            end
          
            def find_vm(vm)
              ems = vm.ext_management_system
              vim = RbVmomi::VIM.connect(:host     => ems.ipaddress || ems.hostname, 
                                         :user     => ems.authentication_userid, 
                                         :password => ems.authentication_password, 
                                         :insecure => true)
              dc = vim.rootFolder.childEntity.first
              recursive_find_vm(dc.vmFolder, vm.name).first
            end
            
            def get_operating_system(vm)
              operating_system = {}
              operating_system[:product_type] = vm.operating_system.product_type
              operating_system[:product_name] = vm.operating_system.product_name
              operating_system[:distribution] = vm.operating_system.distribution    
              operating_system
            end
            
            def get_disks(hardware_id)
              disk_list = []
              disks = @handle.vmdb(:Disk).where(:hardware_id => hardware_id)
              unless disks.empty?
                disks.each do |disk|
                  disk_details = {}
                  disk_details[:controller_type] = disk.controller_type
                  disk_details[:disk_type]       = disk.disk_type
                  disk_details[:filename]        = disk.filename
                  disk_details[:mode]            = disk.mode
                  disk_details[:location]        = disk.location
                  disk_details[:size]            = disk.size
                  disk_details[:size_on_disk]    = disk.size_on_disk
                  disk_details[:partitions]      = get_partitions(disk.id)
                  disk_list << disk_details
                end
              end
              disk_list
            end
            
            def get_partitions(disk_id)
              partition_list = []
              partitions = @handle.vmdb(:Partition).where(:disk_id => disk_id)
              unless partitions.empty?
                partitions.each do |partition|
                  partition_details = {}
                  partition_details[:location]      = partition.location
                  partition_details[:controller]    = partition.controller
                  partition_details[:name]          = partition.name
                  partition_details[:size]          = partition.size
                  partition_details[:start_address] = partition.start_address
                  partition_details[:aligned]       = partition.aligned
                  partition_list << partition_details
                end
              end
              partition_list
            end
            
            def get_volumes(hardware_id)
              volume_list = []
              volumes = @handle.vmdb(:Volume).where(:hardware_id => hardware_id)
              unless volumes.empty?
                volumes.each do |volume|
                  volume_details = {}
                  volume_details[:name]               = volume.name
                  volume_details[:typ]                = volume.typ
                  volume_details[:filesystem]         = volume.filesystem
                  volume_details[:size]               = volume.size
                  volume_details[:free_space]         = volume.free_space
                  volume_details[:used_space_percent] = volume.used_space_percent
                  volume_details[:free_space_percent] = volume.free_space_percent
                  volume_list << volume_details
                end
              end
              volume_list
            end
            
            def get_networks(device_id)
              network_list = []
              networks = @handle.vmdb(:Network).where(:device_id => device_id)
              unless networks.empty?
                networks.each do |network|
                  network_details = {}
                  network_details[:ipaddress]    = network.ipaddress
                  network_details[:ipv6address]  = network.ipv6address
                  network_details[:hostname]     = network.hostname
                  network_details[:dhcp_enabled] = network.dhcp_enabled
                  network_details[:dhcp_server]  = network.dhcp_server
                  network_details[:dns_server]   = network.dns_server
                  network_details[:domain]       = network.domain
                  network_list << network_details
                end
              end
              network_list
            end 
            
            def get_nics(hardware_id, vim_vm)
              nic_list = []
              nics = @handle.vmdb(:GuestDevice).where(["hardware_id = ? AND controller_type = ?", hardware_id, 'ethernet'])
              unless nics.empty?
                nics.each do |nic|
                  nic_details = {}
                  nic_details[:device_name]  = nic.device_name
                  nic_details[:address]      = nic.address
                  nic_details[:manufacturer] = nic.manufacturer
                  rbvmomi_nic = vim_vm.config.hardware.device.grep(RbVmomi::VIM::VirtualEthernetCard).find { |x| x.deviceInfo.label == nic.device_name }
                  nic_details[:adapter_type] = rbvmomi_nic.class.name.demodulize
                  nic_details[:lan_name]     = nic.lan.name rescue nil
                  nic_details[:networks]     = get_networks(nic.id)
                  nic_list << nic_details
                end
              end
              nic_list
            end
            
            def get_guest_applications(vm)
              guest_application_list = []
              unless vm.guest_applications.empty?
                vm.guest_applications.each do | guest_application |
                  guest_application_details = {}
                  guest_application_details[:name]    = guest_application.name
                  guest_application_details[:vendor]  = guest_application.vendor
                  guest_application_details[:version] = guest_application.version
                  guest_application_list << guest_application_details
                end
              end
              guest_application_list
            end

            def get_files(vm)
              file_list = []
              unless vm.files.empty?
                vm.files.each do | file |
                  file_details = {}
                  file_details[:name]     = file.name
                  file_details[:contents] = file.contents if file.contents_available
                  file_list << file_details
                end
              end
              file_list
            end

            def get_system_services(vm)
              system_service_list = []
              system_services = @handle.vmdb(:SystemService).where(:vm => vm.id)
              unless system_services.empty?
                system_services.each do | system_service |
                  system_service_details = {}
                  system_service_details[:name]     = system_service.name
                  system_service_details[:typename] = system_service.typename
                  system_service_list << system_service_details
                end
              end
              system_service_list
            end
                    
            def main
              vms = []
              case @handle.root['vmdb_object_type']
              when 'vm'
                vms << @handle.root['vm']
              else
                vms = @handle.vmdb(:ManageIQ_Providers_Vmware_InfraManager_Vm).all
              end
              Dir.mkdir(OUTPUT_DIRECTORY) unless Dir.exist?(OUTPUT_DIRECTORY)
              vms.each do |vm|
                # next unless vm.name == 'cfme014'
                next if vm.archived or vm.orphaned
                @handle.log(:info, "Processing VM: #{vm.name}")
                vim_vm = find_vm(vm)
                vm_details = {}
                vm_details[:name]                 = vm.name
                vm_details[:hostnames]            = vm.hostnames
                vm_details[:power_state]          = vm.power_state
                vm_details[:operating_system]     = get_operating_system(vm)
                vm_details[:last_scan_on]         = vm.last_scan_on
                vm_details[:cpu_total_cores]      = vm.cpu_total_cores
                hardware = vm.hardware
                vm_details[:cpu_cores_per_socket] = hardware.cpu_cores_per_socket
                vm_details[:cpu_sockets]          = hardware.cpu_sockets
                vm_details[:memory_mb]            = hardware.memory_mb
                vm_details[:disks]                = get_disks(hardware.id)
                vm_details[:volumes]              = get_volumes(hardware.id)
                vm_details[:nics]                 = get_nics(hardware.id, vim_vm)
                vm_details[:guest_applications]   = get_guest_applications(vm)
                vm_details[:files]                = get_files(vm)
                vm_details[:system_services]      = get_system_services(vm)
                case @handle.object['return_format']
                when 'json'
                  return_string = "#{JSON.generate(vm_details)}"
                when 'json_pretty'
                  return_string = "#{JSON.pretty_generate(vm_details)}"
                end
                case @handle.object['output']
                when 'log'
                  @handle.log(:info, "\n#{return_string}")
                when 'file'
                  File.open(OUTPUT_DIRECTORY + "/#{vm.name}.#{@handle.object['return_format']}", "w") do |line|
                    line.puts "#{return_string}"
                  end
                end  
              end
            end
          end
        end
      end
    end
  end
end

ManageIQ::Automate::Transformation::Analytics::Methods::VMDiscovery.new.main
