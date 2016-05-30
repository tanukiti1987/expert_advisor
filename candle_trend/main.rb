require 'active_support'
require 'active_support/core_ext'
require 'oanda_api'
require 'json'
require 'pry'

%w(api_client candle signals order_agent position_agent).each do |rb_file|
  require "./#{rb_file}.rb"
end

# Process.daemon

@signal         = OrderSignal.new
@position_agent = PositionAgent.new
@order_agent    = OrderAgent.new(@position_agent)

signal_thread = Thread.new do
  loop do
    @signal.update
    sleep 1
  end
end

position_agent_thread = Thread.new do
  loop do
    @position_agent.update
    sleep 1
  end
end

order_agent_thread = Thread.new do
  loop do
    @order_agent.trade
    sleep 1
  end
end

signal_thread.join
position_agent_thread.join
order_agent_thread.join
