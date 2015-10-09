# encoding: utf-8
require "socket"

#This is only used by the tests; any problems here are not as important as elsewhere
class RelpClient < Relp

  def initialize(host,port,required_commands = [], options={})
    buffer_size             = options[:buffer_size] || 128
    retransmission_timeout  = options[:retransmission_timeout] || 10
    ssl                     = options[:ssl] || false
    @logger = Cabin::Channel.get(LogStash)
    @logger.info? and @logger.info("Starting RELP client", :host => host, :port => port)
    @server = false
    @buffer = Hash.new

    @buffer_size = buffer_size
    @retransmission_timeout = retransmission_timeout

    #These are things that are part of the basic protocol, but only valid in one direction (rsp, close etc.)
    @basic_relp_commands = ['serverclose','rsp']#TODO: check for others

    #These are extra commands that we require, otherwise refuse the connection
    @required_relp_commands = required_commands

    @socket=TCPSocket.new(host,port)

    if ssl
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params(verify_mode: OpenSSL::SSL::VERIFY_NONE)
      @socket = OpenSSL::SSL::SSLSocket.new(@socket, ctx).tap do |socket|
        socket.sync_close = true
        socket.connect
      end
    end

    #This'll start the automatic frame numbering
    @lasttxnr = 0

    offer=Hash.new
    offer['command'] = 'open'
    offer['message'] = 'relp_version=' + RelpVersion + "\n"
    offer['message'] += 'relp_software=' + RelpSoftware + "\n"
    offer['message'] += 'commands=' + @required_relp_commands.join(',')#TODO: add optional ones
    self.frame_write(@socket, offer)
    response_frame = self.frame_read(@socket)
    if response_frame['message'][0,3] != '200'
      raise RelpError,response_frame['message']
    end

    response=Hash[*response_frame['message'][7..-1].scan(/^(.*)=(.*)$/).flatten]
    if response['relp_version'].nil?
      #if no version specified, relp spec says we must close connection
      self.close()
      raise RelpError, 'No relp_version specified; offer: '
      + response_frame['message'][6..-1].scan(/^(.*)=(.*)$/).flatten

      #subtracting one array from the other checks to see if all elements in @required_relp_commands are present in the offer
    elsif ! (@required_relp_commands - response['commands'].split(',')).empty?
      #if it can't receive syslog it's useless to us; close the connection
      self.close()
      raise InsufficientCommands, response['commands'] + ' offered, require '
      + @required_relp_commands.join(',')
    end
    #If we've got this far with no problems, we're good to go
    @logger.info? and @logger.info("Connection establish with server")

    #This thread deals with responses that come back
    reader = Thread.start do
      loop do
        begin
          f = self.frame_read(@socket)
        rescue
          # ignore exceptions and quit thread
          break
        end
        if f['command'] == 'rsp' && f['message'] == '200 OK'
          @buffer.delete(f['txnr'])
        elsif f['command'] == 'rsp' && f['message'][0,1] == '5'
          #TODO: What if we get an error for something we're already retransmitted due to timeout?
          new_txnr = self.frame_write(@socket, @buffer[f['txnr']])
          @buffer[new_txnr] = @buffer[f['txnr']]
          @buffer.delete(f['txnr'])
        elsif f['command'] == 'serverclose' || f['txnr'] == @close_txnr
          break
        else
          #Don't know what's going on if we get here, but it can't be good
          raise RelpError#TODO: raising errors like this makes no sense
        end
      end
    end

    #While this one deals with frames for which we get no reply
    Thread.start do
      old_buffer = Hash.new
      loop do
        begin
          #This returns old txnrs that are still present
          (@buffer.keys & old_buffer.keys).each do |txnr|
            new_txnr = self.frame_write(@socket, @buffer[txnr])
            @buffer[new_txnr] = @buffer[txnr]
            @buffer.delete(txnr)
          end
          old_buffer = @buffer
          sleep @retransmission_timeout
        rescue
          # ignore exceptions and quit thread
          break
        end
      end
    end
  end

  #TODO: have a way to get back unacked messages on close
  def close
    frame = Hash.new
    frame['command'] = 'close'
    @close_txnr=self.frame_write(@socket, frame)
    #TODO: ought to properly wait for a reply etc. The serverclose will make it work though
    sleep @retransmission_timeout
    return @buffer
  ensure
    @socket.close
  end

  def syslog_write(logline)

    #If the buffer is already full, wait until a gap opens up
    sleep 0.1 until @buffer.length<@buffer_size

    frame = Hash.new
    frame['command'] = 'syslog'
    frame['message'] = logline

    txnr = self.frame_write(@socket, frame)
    @buffer[txnr] = frame
  end

  def nexttxnr
    @lasttxnr += 1
  end

end
