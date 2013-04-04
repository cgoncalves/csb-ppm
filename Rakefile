require 'bundler/setup'
Bundler.require(:default)

require './api'
require 'resque/tasks'

task "resque:setup" do
      ENV['QUEUE'] = '*'
end

task "jobs:work" => "resque:work"
