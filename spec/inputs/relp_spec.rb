# encoding: utf-8
require_relative "../spec_helper"
require_relative "../support/ssl"

describe LogStash::Inputs::Relp do

  before do
    srand(RSpec.configuration.seed)
  end

  describe "registration and close" do

    it "should register without errors" do
      input = LogStash::Plugin.lookup("input", "relp").new("port" => 1234)
      expect {input.register}.to_not raise_error
    end

  end

  describe "when interrupting the plugin" do

    let(:port) { rand(1024..65532) }

    it_behaves_like "an interruptible input plugin" do
      let(:config) { { "port" => port } }
    end
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

    it "should do multiple connections" do
      nclients.times do |client_id|
        expect(events).to have(nevents).with("Hello from client#{client_id}")
      end
    end
  end

  describe "SSL support" do

    let(:nevents) { 100 }
    let(:certificate) { RelpTest.certificate }
    let(:port)        { 5513 }

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

    let(:events) do
      input(conf, nevents) do
        nevents.times do
          client.syslog_write("Hello from client")
        end
      end
    end

    context "registration and close" do

      it "should register without errors" do
        input = LogStash::Plugin.lookup("input", "relp").new("port" => 1235, "ssl_enable" => true,
                                                             "ssl_cert" => certificate.ssl_cert,
                                                             "ssl_key" => certificate.ssl_key)
        expect {input.register}.to_not raise_error
      end

    end

    it "should generated the events as expected" do
      expect(events).to have(nevents).with("Hello from client")
    end

  end

end
