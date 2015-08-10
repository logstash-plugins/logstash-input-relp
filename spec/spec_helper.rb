# encoding: utf-8
require "logstash/devutils/rspec/spec_helper"
require "socket"
require "support/client"

module RelpHelpers

  def setup_clients(number_of_clients, port)
    number_of_clients.times.inject([]) do |clients|
      clients << RelpClient.new("0.0.0.0", port, ["syslog"])
    end
  end

  def filter(events, message)
     events.select{|event| event["message"] == message }
  end

  def input(config, size, &block)
    pipeline = LogStash::Pipeline.new(config)
    queue = Queue.new

    pipeline.instance_eval do
      # create closure to capture queue
      @output_func = lambda { |event| queue << event }

      # output_func is now a method, call closure
      def output_func(event)
        @output_func.call(event)
      end
    end

    pipeline_thread = Thread.new { pipeline.run }
    sleep 0.1 while !pipeline.ready?

    block.call
    sleep 0.1 while queue.size != size

    result = size.times.inject([]) do |acc|
      acc << queue.pop
    end

    pipeline.shutdown
    pipeline_thread.join

    result
  end # def input

end

RSpec.configure do |c|
  c.include RelpHelpers
end

RSpec::Matchers.define :have do |nevents|

  match do |events|
    filter(events, @pattern).size == nevents
  end

  chain :with do |pattern|
    @pattern = pattern
  end

end
