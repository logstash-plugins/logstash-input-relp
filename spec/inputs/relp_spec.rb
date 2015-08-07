# encoding: utf-8
require "logstash/util/relp"
require_relative "../spec_helper"

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

  describe "ssl support" do
  end

  describe "multiple client connections" do

    let(:nclients) { rand(200) }
    let(:nevents)  { 100 }
    let(:port)     { 5512 }

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

    let(:clients) { setup_clients(nclients, port) }

    let(:events) do
      input(conf, (nevents*nclients)) do
        nevents.times do |value|
          clients.each_with_index do |client, index|
            client.syslog_write("Hello from client#{index}")
          end
        end
      end
    end

    it "should do two client connections" do
      nclients.times do |client_id|
        expect(filter(events,  "Hello from client#{client_id}").size).to eq(nevents)
      end
    end

  end
end
