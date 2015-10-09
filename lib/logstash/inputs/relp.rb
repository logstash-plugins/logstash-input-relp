# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "logstash/util/relp"
require "logstash/util/socket_peer"

# Read RELP events over a TCP socket.
#
# For more information about RELP, see
# <http://www.rsyslog.com/doc/imrelp.html>
#
# This protocol implements application-level acknowledgements to help protect
# against message loss.
#
# Message acks only function as far as messages being put into the queue for
# filters; anything lost after that point will not be retransmitted
class LogStash::Inputs::Relp < LogStash::Inputs::Base
  config_name "relp"

  default :codec, "plain"

  # The address to listen on.
  config :host, :validate => :string, :default => "0.0.0.0"

  # The port to listen on.
  config :port, :validate => :number, :required => true

  # Enable SSL (must be set for other `ssl_` options to take effect).
  config :ssl_enable, :validate => :boolean, :default => false

  # Verify the identity of the other end of the SSL connection against the CA.
  # For input, sets the field `sslsubject` to that of the client certificate.
  config :ssl_verify, :validate => :boolean, :default => true

  # The SSL CA certificate, chainfile or CA path. The system CA path is automatically included.
  config :ssl_cacert, :validate => :path

  # SSL certificate path
  config :ssl_cert, :validate => :path

  # SSL key path
  config :ssl_key, :validate => :path

  # SSL key passphrase
  config :ssl_key_passphrase, :validate => :password, :default => nil

  def initialize(*args)
    super(*args)
    @relp_server = nil
  end # def initialize

  public
  def register
    @logger.info("Starting relp input listener", :address => "#{@host}:#{@port}")
    if @ssl_enable
      initialize_ssl_context
      if @ssl_verify == false
        @logger.warn [
          "** WARNING ** Detected UNSAFE options in relp input configuration!",
          "** WARNING ** You have enabled encryption but DISABLED certificate verification.",
          "** WARNING ** To make sure your data is secure change :ssl_verify to true"
        ].join("\n")
      end
    end
    @relp_server = RelpServer.new(@host, @port,['syslog'], @ssl_context)
  end # def register

  private
  def initialize_ssl_context
    require "openssl"

    @ssl_context = OpenSSL::SSL::SSLContext.new
    @ssl_context.cert = OpenSSL::X509::Certificate.new(File.read(@ssl_cert))
    @ssl_context.key = OpenSSL::PKey::RSA.new(File.read(@ssl_key),@ssl_key_passphrase.value)
    if @ssl_verify
      @cert_store = OpenSSL::X509::Store.new
      # Load the system default certificate path to the store
      @cert_store.set_default_paths
      if !@ssl_cacert.nil?
        if File.directory?(@ssl_cacert)
          @cert_store.add_path(@ssl_cacert)
        else
          @cert_store.add_file(@ssl_cacert)
        end
      end
      @ssl_context.cert_store = @cert_store
      @ssl_context.verify_mode = OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    end
  end

  private
  def relp_stream(relpserver,socket,output_queue,client_address)
    while !stop?
      frame = relpserver.syslog_read(socket)
      @codec.decode(frame["message"]) do |event|
        decorate(event)
        event["host"] = client_address
        event["sslsubject"] ||= socket.peer_cert.subject if @ssl_enable && @ssl_verify
        output_queue << event
      end

      #To get this far, the message must have made it into the queue for
      #filtering. I don't think it's possible to wait for output before ack
      #without fundamentally breaking the plugin architecture
      relpserver.ack(socket, frame['txnr'])
    end
  end

  public
  def run(output_queue)
    while !stop?
      begin
        # Start a new thread for each connection.
        Thread.start(@relp_server.accept) do |client|
            rs = client[0]
            socket = client[1]
          begin
            rs.relp_setup_connection(socket)
            # monkeypatch a 'peer' method onto the socket.
            socket.instance_eval { class << self; include ::LogStash::Util::SocketPeer end }
            peer = socket.peer
            @logger.debug("Relp Connection to #{peer} created")
            relp_stream(rs,socket, output_queue, peer)
          rescue Relp::ConnectionClosed => e
            @logger.debug("Relp Connection to #{peer} Closed")
          rescue Relp::RelpError => e
            @logger.warn('Relp error: '+e.class.to_s+' '+e.message)
            #TODO: Still not happy with this, are they all warn level?
            #Will this catch everything I want it to?
            #Relp spec says to close connection on error, ensure this is the case
          ensure
            socket.close rescue nil
          end
        end # Thread.start
      rescue Relp::InvalidCommand,Relp::InappropriateCommand => e
        @logger.warn('Relp client trying to open connection with something other than open:'+e.message)
      rescue Relp::InsufficientCommands
        @logger.warn('Relp client incapable of syslog')
      rescue Relp::ConnectionClosed
        @logger.debug('Relp Connection closed')
      rescue OpenSSL::SSL::SSLError => ssle
        # NOTE(mrichar1): This doesn't return a useful error message for some reason
        @logger.error("SSL Error", :exception => ssle, :backtrace => ssle.backtrace)
      rescue IOError
        # if stop is called during @server_socket.accept
        # the thread running `run` will raise an IOError
        # We catch IOError here and do nothing, just let the method terminate
      end
    end # loop
  end # def run

  def stop
    if @relp_server
      @relp_server.shutdown rescue nil
      @relp_server = nil
    end
  end
end # class LogStash::Inputs::Relp

#TODO: structured error logging
