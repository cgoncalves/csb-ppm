require 'sinatra'
require "sinatra/reloader" if development?
require 'cloudfoundry-manager'

module Cloudfoundry
  module Manager
    class Server

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
        Cloudfoundry::Manager.load_config('clouds.yaml')
        bootstrap = Cloudfoundry::Manager::Bootstrap.new(params['host'], params['user'], params['password'])
        #bootstrap.vcap_dir = "/home/#{params['user']}/vcap"
        #bootstrap.upload_file('/Users/cgoncalves/Downloads/vcap-HEAD.tar', "/home/#{params['user']}/vcap-HEAD.tar")
        #bootstrap.deploy(params['id'], params['location'], params['domain'])
        bootstrap.setup(params['id'], params['location'], params['domain'])
        status 200
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
