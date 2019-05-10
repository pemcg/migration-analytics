#!/usr/bin/env ruby
#
# get_token
#
require 'rest-client'
require 'json'
require 'optparse'

begin
  options = {
            :server     => 'localhost',
            :username   => nil,
            :password   => nil
            }
  parser = OptionParser.new do|opts|
    opts.banner = "Usage: get_token.rb [options]"
    opts.on('-s', '--server server', 'CloudForms server to connect to') do |server|
      options[:server] = server
    end
    opts.on('-u', '--username username', 'Username to connect as') do |username|
      options[:username] = username
    end
    opts.on('-p', '--password password', 'Password') do |password|
      options[:password] = password
    end
    opts.on('-h', '--help', 'Displays Help') do
      puts opts
      exit!
    end
  end
  parser.parse!
  
  if options[:username].nil?
    username = "admin"
  else
    username = options[:username]
  end
  if options[:password].nil?
    password = "smartvm"
  else
    password = options[:password]
  end
  
  api_uri = "https://#{server}/api"
  #
  # Get an authentication token
  #
  url = URI.encode(api_uri + '/auth')
  rest_return = RestClient::Request.execute(method:      :get,
                                              url:        url,
                                              :user       => username,
                                              :password   => password,
                                              :headers    => {:accept => :json},
                                              verify_ssl: false)
  auth_token = JSON.parse(rest_return)['auth_token']
  if auth_token.nil?
    raise "Couldn't get an authentication token"
  else
    puts "Authentication token: #{auth_token}"
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
  puts "[#{err}]\n#{err.backtrace.join("\n")}"
  exit!
end