# encoding: utf-8
require_relative "../spec_helper"
require "logstash/devutils/rspec/shared_examples"
require_relative "../support/ssl"

describe LogStash::Inputs::Relp do

  let!(:helper) { RelpHelpers.new }

  before do
    srand(RSpec.configuration.seed)
  end

  describe "registration and close" do

    it "should register without errors" do
      input = LogStash::Plugin.lookup("input", "relp").new("port" => 1234)
      expect {input.register}.to_not raise_error
      input.close rescue nil
    end
  end

  describe "when interrupting the plugin" do
    let(:port) { rand(1024..65532) }

    it_behaves_like "an interruptible input plugin" do
      let(:config) { { "port" => port } }
    end
  end

  describe "multiple client connections" do

    # (colinsurprenant) don't put number of simultaneous clients too high,
    # it seems to lock no sure why. the test client code needs a very serious,
    # refactoring, its too complex and very hard to debug :P
    let(:nclients) { rand(10) }

    let(:nevents)  { 100 }
    let(:port) { rand(1024..65532) }

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

    let(:clients) { RelpHelpers.setup_clients(nclients, port) }

    let(:events) do
      input(conf) do |pipeline, queue|
        nevents.times do |value|
          clients.each_with_index do |client, index|
            client.syslog_write("Hello from client#{index}")
          end
        end
        (nevents * nclients).times.collect { queue.pop }
      end
    end

    after :each do
      clients.each do |client|
        client.close rescue nil
      end
    end

    it "should do multiple connections" do
      expect(events.size).to eq(nevents * nclients)
      grouped = events.group_by { |e| /(client\d)/.match(e.get("message")) }
      expect(grouped.size).to eq(nclients)
    end
  end

  describe "SSL support" do

    let(:certificate) { RelpTest.certificate }
    let(:port) { rand(1024..65532) }

    context "events reading" do

      let(:nevents) { 100 }

      let(:conf) do
        <<-CONFIG
          input {
            relp {
              type => "blah"
              port => #{port}
              ssl_enable => true
              ssl_verify => false
              ssl_cert => "#{certificate.ssl_cert}"
              ssl_key  => "#{certificate.ssl_key}"
           }
         }
        CONFIG
      end

      let(:client) { RelpClient.new("0.0.0.0", port, ["syslog"], {:ssl => true}) }

      let!(:events) do
        input(conf) do |pipeline, queue|
          nevents.times do
            client.syslog_write("Hello from client")
          end
          nevents.times.collect { queue.pop }
        end
      end

      after :each do
        client.close rescue nil
      end

      it "should generated the events as expected" do
        expect(events).to have(nevents).with("Hello from client")
      end
    end

    context "registration and close" do

      it "should register without errors" do
        input = LogStash::Plugin.lookup("input", "relp").new(
          "port" => port,
          "ssl_enable" => true,
          "ssl_cert" => certificate.ssl_cert,
          "ssl_key" => certificate.ssl_key
        )
        expect {input.register}.to_not raise_error
        input.close rescue nil
      end
    end
  end
end
