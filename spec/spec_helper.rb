# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "logstash/inputs/relp"
require "logstash/util/relp"
require "socket"
require "support/client"

class RelpHelpers

  def self.setup_clients(number_of_clients, port)
    number_of_clients.times.inject([]) do |clients|
      clients << RelpClient.new("0.0.0.0", port, ["syslog"])
    end
  end

  def self.filter(events, message)
     events.select{|event| event["message"] == message }
  end

end

RSpec::Matchers.define :have do |nevents|

  match do |events|
    RelpHelpers.filter(events, @pattern).size == nevents
  end

  chain :with do |pattern|
    @pattern = pattern
  end

end
