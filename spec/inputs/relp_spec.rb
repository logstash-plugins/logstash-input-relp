# coding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "socket"
require "logstash/util/relp"

describe "inputs/relp" do

  it "should do single client connection" do
    event_count = 10
    port = 5511
    conf = <<-CONFIG
    input {
      relp {
        type => "blah"
        port => #{port}
      }
    }
    CONFIG

    events = input(conf) do |pipeline, queue|
      client = RelpClient.new("0.0.0.0", port, ["syslog"])
      event_count.times do |value|
        client.syslog_write("Hello #{value}")
      end
      event_count.times.collect { queue.pop }
    end

    event_count.times do |i|
      insist { events[i]["message"] } == "Hello #{i}"
    end
  end

  it "should do two client connection" do
    event_count = 100
    port = 5512
    conf = <<-CONFIG
    input {
      relp {
        type => "blah"
        port => #{port}
      }
    }
    CONFIG

    events = input(conf) do |pipeline, queue|
      client = RelpClient.new("0.0.0.0", port, ["syslog"])
      client2 = RelpClient.new("0.0.0.0", port, ["syslog"])

      event_count.times do
        client.syslog_write("Hello from client")
        client2.syslog_write("Hello from client 2")
      end

      (event_count * 2).times.map{queue.pop}
    end

    insist { events.select{|event| event["message"] == "Hello from client" }.size } == event_count
    insist { events.select{|event| event["message"] == "Hello from client 2" }.size } == event_count
  end
end
