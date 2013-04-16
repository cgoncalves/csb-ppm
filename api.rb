require 'sinatra'
require "sinatra/reloader" if development?
require 'cloudfoundry-manager'
require 'resque'
require 'sinatra/redis'

configure do
  uri = URI.parse(ENV["REDISTOGO_URL"])
  Resque.redis = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
  Resque.redis.namespace = "resque:example"
  set :redis, ENV["REDISTOGO_URL"]
end

class StartJob
  @queue = "ppm"

  def self.perform(config)
      paas = Cloudfoundry::Manager::Bootstrap.new(config[:ssh][:host], config[:ssh][:user], config[:ssh][:password])
      paas.start
  rescue Resque::TermException
    Resque.enqueue(self, id)
  end
end

class SetupJob
  @queue = "ppm"

  def self.perform(host, user, password, id, domain, ip, callback)
      puts "Running setup..."
      Cloudfoundry::Manager.load_config('clouds.yaml')
      paas = Cloudfoundry::Manager::Bootstrap.new(host, user, password)
      paas.setup(id, domain, ip)
      puts "Setup about to end. Calling POST callback"
      require 'net/http'
      uri = URI.parse(URI.unescape(callback))
      req = Net::HTTP::Post.new(url.path)
      req.basic_auth 'portal', 'qwerty321' # TODO
      res = Net::HTTP.new(url.host, url.port).start {|http| http.request(req) }
      case res
      when Net::HTTPSuccess, Net::HTTPRedirection
        # OK
      else
        res.error!
      end
      puts "Finished running setup!"
  end
end

module Cloudfoundry
  module Manager
    class Server < Sinatra::Base

      helpers do
        def protected!
          unless authorized?
            response['WWW-Authenticate'] = %(Basic realm="Restricted Area")
            throw(:halt, [401, "Not authorized\n"])
          end
        end

        def authorized?
          @auth ||=  Rack::Auth::Basic::Request.new(request.env)
          @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == ['admin', 'admin'] # FIXME
        end
      end

      get '/providers' do
        protected!
        content_type :json
        config = Cloudfoundry::Manager.load_config('clouds.yaml')
        JSON.pretty_generate(config['clouds'])
      end

      post '/setup' do
        #protected!
        puts "Enqueuing setup"
        Resque.enqueue(SetupJob, params['host'], params['user'], params['password'], params['id'], params['domain'], params['ip'], params['callback'])
        puts "Enqueued setup"
        status 202
      end

      post '/start' do
        puts "Executing PaaS start operation"
        Cloudfoundry::Manager.load_config('clouds.yaml')
        configs = Cloudfoundry::Manager.config['clouds'].select{ |p| p[:id] == params[:id] }
        return status 404 if configs.nil? or configs.empty?
        Resque.enqueue(StartJob, configs.first)
        puts "Ended executing PaaS start operation"
        status 202
      end

      #get '/log' do
      #  #protected!
      #  Cloudfoundry::Manager::Bootstrap.log(params['domain'])
      #end

      get '/components' do
        protected!
        content_type :json

        opts = {}
        opts[:nats_host] = params['nats_host'] if params['nats_host']
        opts[:nats_user] = params['nats_user'] if params['nats_user']
        opts[:nats_password] = params['nats_password'] if params['nats_password']
        opts[:nats_port] = params['nats_port'] if params['nats_port']
        opts[:timeout] = params['timeout'].to_i if params['timeout']

        Cloudfoundry::Manager.load_config('clouds.yaml')
        JSON.pretty_generate(Cloudfoundry::Manager::Discovery.new(opts).find_all)
      end

      get '/components/:component' do
        content_type :json
        protected!
        Cloudfoundry::Manager.load_config('clouds.yaml')
        JSON.pretty_generate(Cloudfoundry::Manager::Discovery.new(params['nats_host'], params['nats_user'], params['nats_password'], params['nats_port'], params['timeout']).find(params['component']))
      end

    end
  end
end
