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
          class VCDiscovery
            require 'rbvmomi'
            require 'yaml'

            OUTPUT_DIRECTORY = "/tmp/migration_analytics".freeze

            def initialize(handle = $evm)
              @handle = handle
            end

            def get_port_groups(dvs)
              port_group_list = []
              unless dvs.lans.empty?
                dvs.lans.each do |lan|
                  lan_details = {}
                  lan_details[:name] = lan.name
                  lan_details[:tag]  = lan.tag
                  port_group_list << lan_details
                end
              end
              port_group_list
            end
           
            def get_distributed_switches(host)
              dvs_list = []
              unless host.switches.empty?
                host.switches.each do |switch|
                  next unless switch.type == 'ManageIQ::Providers::Vmware::InfraManager::DistributedVirtualSwitch'
                  dvs_details = {}
                  dvs_details[:name]        = switch.name
                  dvs_details[:ports]       = switch.ports
                  dvs_details[:port_groups] = get_port_groups(switch)
                  dvs_list << dvs_details
                end
              end
              dvs_list
            end

            def get_host_switches(host)
              switch_list = []
              unless host.switches.empty?
                host.switches.each do |switch|
                  next unless switch.type == 'ManageIQ::Providers::Vmware::InfraManager::HostVirtualSwitch'
                  switch_details = {}
                  switch_details[:name]        = switch.name
                  switch_details[:ports]       = switch.ports
                  switch_details[:port_groups] = get_port_groups(switch)
                  switch_list << switch_details
                end
              end
              switch_list
            end
            
            def get_datacenters(ems_id)
              dc_list = []
              dcs = @handle.vmdb(:EmsCluster).where(:ems_id => ems_id).collect { |cluster| cluster.v_parent_datacenter }
              unless dcs.empty?
                dcs.each do |dc|
                  dc_details = {}
                  dc_details[:name]              = dc
                  dc_details[:ems_clusters]      = get_clusters(ems_id, dc)
                  dc_details[:shared_datastores] = get_shared_datastores(ems_id)
                  dc_list << dc_details
                end
              end
              dc_list
            end
            
            def get_clusters(ems_id, dc)
              cluster_list = []
              clusters = @handle.vmdb(:EmsCluster).where(:ems_id => ems_id)
              unless clusters.empty?
                clusters.each do |cluster|
                  next unless cluster.v_parent_datacenter == dc
                  cluster_details = {}
                  cluster_details[:name]                       = cluster.name
                  cluster_details[:aggregate_physical_cpus]    = cluster.aggregate_physical_cpus
                  cluster_details[:aggregate_cpu_total_cores]  = cluster.aggregate_cpu_total_cores
                  cluster_details[:aggregate_cpu_speed]        = cluster.aggregate_cpu_speed
                  cluster_details[:aggregate_memory]           = cluster.aggregate_memory
                  cluster_details[:effective_cpu]              = cluster.effective_cpu
                  cluster_details[:effective_memory]           = cluster.effective_memory
                  cluster_details[:aggregate_vm_cpus]          = cluster.aggregate_vm_cpus
                  cluster_details[:aggregate_vm_memory]        = cluster.aggregate_vm_memory
                  cluster_details[:drs_enabled]                = cluster.drs_enabled
                  cluster_details[:drs_automation_level]       = cluster.drs_automation_level
                  cluster_details[:drs_migration_threshold]    = cluster.drs_migration_threshold
                  cluster_details[:ha_enabled]                 = cluster.ha_enabled
                  cluster_details[:ha_admit_control]           = cluster.ha_admit_control
                  cluster_details[:ha_max_failures]            = cluster.ha_max_failures
                  cluster_details[:total_direct_vms]           = cluster.total_direct_vms
                  cluster_details[:total_direct_miq_templates] = cluster.total_direct_miq_templates
                  cluster_details[:v_cpu_vr_ratio]             = cluster.v_cpu_vr_ratio
                  cluster_details[:v_ram_vr_ratio]             = cluster.v_ram_vr_ratio
                  cluster_details[:hosts]                      = get_hosts(cluster.id)
                  cluster_list << cluster_details
                end
              end
              cluster_list
            end

            def get_hosts(ems_cluster_id)
              host_list = []
              hosts = @handle.vmdb(:ManageIQ_Providers_Vmware_InfraManager_HostEsx).where(:ems_cluster_id => ems_cluster_id)
              unless hosts.empty?
                hosts.each do |host|
                  host_details = {}
                  host_details[:name]                         = host.name
                  host_details[:power_state]                  = host.power_state
                  host_details[:vmm_product]                  = host.vmm_product
                  host_details[:vmm_version]                  = host.vmm_version
                  host_details[:vmm_buildnumber]              = host.vmm_buildnumber
                  host_details[:num_cpu]                      = host.num_cpu
                  host_details[:cpu_total_cores]              = host.cpu_total_cores
                  host_details[:cpu_cores_per_socket]         = host.cpu_cores_per_socket
                  host_details[:hyperthreading]               = host.hyperthreading
                  host_details[:ram_size]                     = host.ram_size
                  host_details[:v_total_vms]                  = host.v_total_vms
                  host_details[:v_total_miq_templates]        = host.v_total_miq_templates
                  host_details[:host_switches]                = get_host_switches(host)
                  host_details[:distributed_switches]         = get_distributed_switches(host)
                  host_details[:datastores]                   = get_host_datastores(host)
                  host_list << host_details
                end
              end
              host_list
            end

            def get_host_datastores(host)
              datastore_list = []
              unless host.storages.empty?
                host.storages.each do |datastore|
                  next unless datastore.multiplehostaccess.zero?
                  datastore_details = {}
                  datastore_details[:name]                          = datastore.name
                  datastore_details[:store_type]                    = datastore.store_type
                  datastore_details[:raw_disk_mappings_supported]   = datastore.raw_disk_mappings_supported
                  datastore_details[:thin_provisioning_supported]   = datastore.thin_provisioning_supported
                  datastore_details[:directory_hierarchy_supported] = datastore.directory_hierarchy_supported
                  datastore_details[:total_space]                   = datastore.total_space
                  datastore_details[:uncommitted]                   = datastore.uncommitted
                  datastore_details[:free_space]                    = datastore.free_space
                  datastore_details[:v_total_vms]                   = datastore.v_total_vms
                  datastore_details[:storage_profiles]              = datastore.storage_profiles.pluck(:name)
                  datastore_list << datastore_details
                end
              end
              datastore_list
            end

            def get_shared_datastores(ems_id)
              datastore_list = []
              datastores = @handle.vmdb(:Storage).all
              unless datastores.empty?
                datastores.each do |datastore|
                  next unless datastore.ext_management_systems.first.id == ems_id and not datastore.multiplehostaccess.zero?
                  datastore_details = {}
                  datastore_details[:name]                          = datastore.name
                  datastore_details[:store_type]                    = datastore.store_type
                  datastore_details[:raw_disk_mappings_supported]   = datastore.raw_disk_mappings_supported
                  datastore_details[:thin_provisioning_supported]   = datastore.thin_provisioning_supported
                  datastore_details[:directory_hierarchy_supported] = datastore.directory_hierarchy_supported
                  datastore_details[:total_space]                   = datastore.total_space
                  datastore_details[:uncommitted]                   = datastore.uncommitted
                  datastore_details[:free_space]                    = datastore.free_space
                  datastore_details[:v_total_vms]                   = datastore.v_total_vms
                  datastore_details[:hosts]                         = datastore.hosts.pluck(:name)
                  datastore_details[:storage_profiles]              = datastore.storage_profiles.pluck(:name)
                  datastore_list << datastore_details
                end
              end
              datastore_list
            end

            def about(vim)
              vim.serviceContent.about
            end

            def get_extension_servers(extension)
              extension_servers = []
              extension.server.each do |server|
                server_details = {}
                server_details[:company]     = server.company
                server_details[:description] = server.description.label
                server_details[:url]         = server.url
                server_details[:type]        = server.type
                extension_servers << server_details
              end
              extension_servers
            end

            def get_registered_extensions(vim)

              # NSX-V uses the com.vmware.vShieldManager string 
              # NSX-T uses the com.vmware.nsx.management.nsxt string 

              extensions = []
              vim.serviceContent.extensionManager.extensionList.each do |extension|
                extension_details = {}
                extension_details[:key]         = extension.key
                extension_details[:company]     = extension.company
                extension_details[:label]       = extension.description.label
                extension_details[:summary]     = extension.description.summary
                extension_details[:version]     = extension.version
                extension_details[:servers]     = get_extension_servers(extension)
                extensions << extension_details
              end
              extensions
            end

            def get_license_properties(license)
              license_properties = {}
              license.properties.each do |property|
                if property.value.class.to_s =~ /LicenseManager.*?Info/
                  license_properties[property.key] = get_license_properties(property.value)
                else
                  license_properties[property.key] = property.value
                end
              end
              license_properties
            end

            def get_license_details(vim)
              licenses = []
              vim.serviceContent.licenseManager.licenseAssignmentManager.QueryAssignedLicenses.each do |license|
                license_details = {}
                license_details[:name]                = license.assignedLicense.name
                license_details[:license_key]         = license.assignedLicense.licenseKey
                license_details[:edition_key]         = license.assignedLicense.editionKey
                license_details[:total]               = license.assignedLicense.total
                license_details[:used]                = license.assignedLicense.used
                license_details[:properties]          = get_license_properties(license)
                licenses << license_details
              end
              licenses
            end
                    
            def main
              vcenters = []
              case @handle.root['vmdb_object_type']
              when 'ext_management_system'
                vcenters << @handle.root['ext_management_system']
              else
                vcenters = @handle.vmdb(:ManageIQ_Providers_Vmware_InfraManager).all
              end
              Dir.mkdir(OUTPUT_DIRECTORY) unless Dir.exist?(OUTPUT_DIRECTORY)
              vcenters.each do |vc|
                next unless vc.type == "ManageIQ::Providers::Vmware::InfraManager"
                @handle.log(:info, "Processing vCenter: #{vc.hostname}")
                vim = RbVmomi::VIM.connect(:host     => vc.ipaddress || vc.hostname, 
                                           :user     => vc.authentication_userid, 
                                           :password => vc.authentication_password, 
                                           :insecure => true)
                about_vc = about(vim)
                vc_details = {}
                vc_details[:hostname]               = vc.hostname
                vc_details[:full_name]              = about_vc[:fullName]
                vc_details[:licenses]               = get_license_details(vim)
                vc_details[:registered_extensions]  = get_registered_extensions(vim)
                vc_details[:datacenters]            = get_datacenters(vc.id)

                case @handle.object['return_format']
                when 'json'
                  return_string = "#{JSON.generate(vc_details)}"
                when 'json_pretty'
                  return_string = "#{JSON.pretty_generate(vc_details)}"
                end
                case @handle.object['output']
                when 'log'
                  @handle.log(:info, "\n#{return_string}")
                when 'file'
                  File.open(OUTPUT_DIRECTORY + "/#{vc.hostname}.#{@handle.object['return_format']}", "w") do |line|
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

ManageIQ::Automate::Transformation::Analytics::Methods::VCDiscovery.new.main
