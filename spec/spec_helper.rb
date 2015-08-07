# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "socket"

module RelpHelpers

  def setup_clients(number_of_clients, port)
    number_of_clients.times.inject([]) do |clients|
      clients << RelpClient.new("0.0.0.0", port, ["syslog"])
    end
  end

end

RSpec.configure do |c|
  c.include RelpHelpers
end
