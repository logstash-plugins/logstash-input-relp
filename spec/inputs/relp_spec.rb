# coding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "socket"
require "logstash/util/relp"

describe "inputs/relp" do

  before do
    srand(RSpec.configuration.seed)
  end

  describe "registration and teardown" do

    it "should register without errors" do
      input = LogStash::Plugin.lookup("input", "relp").new("port" => 1234)
      expect {input.register}.to_not raise_error
    end

  end

  describe "multiple client connections" do

    let(:nclients) { rand(200) }
    let(:nevents) { 100 }
    let(:port)   { 5512 }
    let(:type)   { "blah" }

    let(:conf) do
      <<-CONFIG
        input {
          relp {
            type => "blah"
            port => #{port}
         }
       }
      CONFIG
    end

    let(:clients) do
      nclients.times.inject([]) do |clients|
        clients << RelpClient.new("0.0.0.0", port, ["syslog"])
      end
    end

    let(:events) do input(conf) do |pipeline, queue|
      nevents.times do |value|
        clients.each_with_index do |client, index|
          client.syslog_write("Hello from client#{index}")
        end
      end
      (nevents * nclients).times.collect { queue.pop }
    end
    end

    it "should do two client connections" do
      nclients.times do |client_id|
        client_events = events.select{|event| event["message"] == "Hello from client#{client_id}" }
        expect(client_events.size).to eq(nevents)
      end
    end

  end
end
