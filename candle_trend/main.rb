require 'active_support'
require 'active_support/core_ext'
require 'oanda_api'
require 'json'

%w(api_client candle signals order_agent position_agent).each do |rb_file|
  require "./#{rb_file}.rb"
end

Process.daemon

@signal         = OrderSignal.new
@position_agent = PositionAgent.new
@order_agent    = OrderAgent.new(@position_agent)

Thread.start do
  loop do
    @signal.update
    sleep 10
  end
end

Thread.start do
  loop do
    @position_agent.update
    sleep 1
  end
end

Thread.start do
  loop do
    @order_agent.trade
    sleep 5
  end
end

sleep 10
