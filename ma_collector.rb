#!/usr/bin/env ruby
#
# ma_collector
#
require 'rest-client'
require 'json'
require 'optparse'

BASE_DIRECTORY = "/tmp/migration_analytics".freeze
VM_DIRECTORY = BASE_DIRECTORY + "/vms".freeze
VC_DIRECTORY = BASE_DIRECTORY + "/vcs".freeze

HOST_RELATIONSHIPS = %q(
switches,
storages).gsub(/\n/, "")

VM_RELATIONSHIPS = %q(
files,
hardware,
hardware.disks,
hardware.networks,
hardware.nics,
hardware.partitions,
hardware.storage_adapters,
hardware.volumes,
lans,
system_services).gsub(/\n/, "")

@options = {
          :server      => 'localhost',
          :token       => nil,
          :vc_username => nil,
          :vc_password => nil
          }

parser = OptionParser.new do|opts|
  opts.banner = "Usage: ma_collector.rb [options]"
  opts.on('-s', '--server server', 'CloudForms server to connect to') do |server|
    @options[:server] = server
  end
  opts.on('-t', '--token authentication_token', 'Authentication token for API connection') do |token|
    @options[:token] = token
  end
  opts.on('-u', '--username username', 'vCenter username (optional)') do |vc_username|
    @options[:vc_username] = vc_username
  end
  opts.on('-p', '--password password', 'vCenter password (optional unless -u specified)') do |vc_password|
    @options[:vc_password] = vc_password
  end
  opts.on('-h', '--help', 'Displays Help') do
    puts opts
    exit!
  end
end
parser.parse!
raise "Authentication token is required (-t argument)" if @options[:token].nil?

def compact_hash(hsh)
  hsh.each do |k,v|
    case v.class.to_s
    when 'Array'
      compact_array(v)
    when 'Hash'
      compact_hash(v)
    else
      hsh.delete(k) if v.nil? || /^$/.match(v.to_s) || /_id$/.match(k)
    end
  end
  hsh
end

def compact_array(arry)
  arry.each do |e|
    compact_hash(e) if e.class.to_s == 'Hash'
  end
  arry
end

def clean(hsh)
  # Remove keys with nil or blank string values, or keys with CloudForms object IDs
  hsh.each do |k,v|
    hsh.delete(k) if v.nil? || /^$/.match(v.to_s) || /_id$/.match(k)
    hsh[k] = compact_hash(v) if v.class.to_s == 'Hash'
    hsh[k] = compact_array(v) if v.class.to_s == 'Array'
  end
  hsh
end

def get_extension_servers(extension)
  extension_servers = []
  extension.server.each do |server|
    server_details = {}
    server_details['company']     = server.company
    server_details['description'] = server.description.label
    server_details['url']         = server.url
    server_details['type']        = server.type
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
    extension_details['key']         = extension.key
    extension_details['company']     = extension.company
    extension_details['label']       = extension.description.label
    extension_details['summary']     = extension.description.summary
    extension_details['version']     = extension.version
    extension_details['servers']     = get_extension_servers(extension)
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
    license_details['name']                = license.assignedLicense.name
    license_details['license_key']         = license.assignedLicense.licenseKey
    license_details['edition_key']         = license.assignedLicense.editionKey
    license_details['total']               = license.assignedLicense.total
    license_details['used']                = license.assignedLicense.used
    license_details['properties']          = get_license_properties(license)
    licenses << license_details
  end
  licenses
end

def get_object_id_list(collection, filter)
  id_list = []
  url = URI.encode(@api_uri + "/#{collection}?filter[]=#{filter}&expand=resources&attributes=id")
  api_return = call_api(:get, url)
  id_list << api_return['resources'].map { |obj| obj['id'] }
  # allow for pagination of returns
  if api_return['pages'] > 1
    while api_return['links'].has_key?('next')
      api_return = call_api(:get, api_return['links']['next'])
      id_list << api_return['resources'].map { |obj| obj['id'] }
    end
  end
  id_list.flatten!
end

def collection_attributes(collection)
  api_return = call_api(:options, URI.encode(@api_uri + "/#{collection}"))
  # return attributes & virtual columns but remove CloudForms-specific IDs which are meaningless to Insights
  (api_return['attributes'] + api_return['virtual_attributes']).select { |option| option !~ /_id$/ }.join(',')
end

def call_api(action, url)
  rest_return = RestClient::Request.execute(method:     action,
                                            url:        url,
                                            :headers    => {:accept        => :json, 
                                                            'x-auth-token' => @options[:token]},
                                            verify_ssl: false)
  JSON.parse(rest_return)
end

def get_host_details(cluster_id)
  host_list = []
  hosts = get_object_id_list('hosts', "ems_cluster_id=#{cluster_id}")
  hosts.each do |host|
    host_details = {}
    url = URI.encode(@api_uri + "/hosts/#{host}?attributes=" + collection_attributes('hosts') + ',' + HOST_RELATIONSHIPS)
    host_details = call_api(:get, url)
    host_details.delete_if { |k,v| /enabled.*ports/.match(k) }
    host_list << host_details
  end
  host_list
end

def get_cluster_details(provider_id)
  cluster_list = []
  clusters = get_object_id_list('clusters', "ems_id=#{provider_id}")
  clusters.each do |cluster|
    cluster_details = {}
    url = URI.encode(@api_uri + "/clusters/#{cluster}?attributes=" + collection_attributes('clusters'))
    cluster_details = call_api(:get, url)
    cluster_details['hosts'] = get_host_details(cluster_details['id'])
    cluster_list << cluster_details
  end
  cluster_list
end

def get_vm_details(vm_id, attributes)
  url = URI.encode(@api_uri + "/vms/#{vm_id}?expand=software&attributes=" + attributes + ',' + VM_RELATIONSHIPS)
  call_api(:get, url)
end

def get_provider_details(provider_id)
  url = URI.encode(@api_uri + "/providers/#{provider_id}?attributes=" + collection_attributes('providers'))
  call_api(:get, url)
end

begin
  @api_uri = "https://#{@options[:server]}/api"
  if @options[:vc_name].nil?
    providers = get_object_id_list('providers', "type=\'ManageIQ::Providers::Vmware::InfraManager\'")
    case providers.length
    when 0
      raise "No VMware providers have been found"
    when 1
      provider_id = providers.first
    else
      raise "Multiple VMware providers have been found, specify a provider name using -n argument"
    end
  else
    provider_id = get_object_id_list('providers', "name=\'#{@options[:vc_name]}\'").first
    raise "Provider \'#{@options[:vc_name]}\' not found" if provider_id.nil?
  end

  FileUtils.mkdir_p(VC_DIRECTORY) unless Dir.exist?(VC_DIRECTORY)
  FileUtils.mkdir_p(VM_DIRECTORY) unless Dir.exist?(VM_DIRECTORY)

  puts "Analyzing vCenter"
  vc_details             = get_provider_details(provider_id)
  vc_details['clusters'] = get_cluster_details(provider_id)
  unless @options[:vc_username].nil? || @options[:vc_password].nil?
    require 'rbvmomi'
    vim = RbVmomi::VIM.connect(:host     => vc_details['hostname'], 
                               :user     => @options[:vc_username], 
                               :password => @options[:vc_password], 
                               :insecure => true)
    vc_details['licenses']              = get_license_details(vim)
    vc_details['registered_extensions'] = get_registered_extensions(vim)
  end
  File.open(VC_DIRECTORY + "/#{vc_details['name']}.json", "w") do |line|
    line.puts "#{JSON.generate(clean(vc_details))}"
  end
  
  puts "Analyzing VMs"
  vm_attributes = collection_attributes('vms')
  vms = get_object_id_list('vms', "ems_id=\'#{provider_id}\'")
  number_of_vms = vms.length
  counter = 0
  vms.each do |vm|
    counter += 1
    vm_details = get_vm_details(vm, vm_attributes)
    File.open(VM_DIRECTORY + "/#{vm_details['name']}.json", "w") do |line|
      line.puts "#{JSON.generate(clean(vm_details))}"
    end
    print "#{counter} of #{number_of_vms} VMs analyzed\r"
  end

rescue RestClient::Exception => err
  unless err.response.nil?
    error = err.response
    puts "The REST request failed with code: #{error.code}"
    puts "The response body was:"
    puts JSON.pretty_generate JSON.parse(error.body)
  end
  exit!
rescue => err
  puts "#{err}\n#{err.backtrace.join("\n")}"
  exit!
end
