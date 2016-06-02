require 'active_support'
require 'active_support/core_ext'
require 'oanda_api'
require 'json'
require 'pry'

%w(api_client candle signals order_agent position_agent).each do |rb_file|
  require "./#{rb_file}.rb"
end

@signal         = OrderSignal.new
@position_agent = PositionAgent.new
@order_agent    = OrderAgent.new(@position_agent)

loop do
  @position_agent.update
  unless @position_agent.has_position?
    @signal.update
    @order_agent.trade
  end
  sleep 1
end
