# Process.daemon
require 'active_support'
require 'active_support/core_ext'
require 'oanda_api'
require 'json'

%w(api_client candle signals).each do |rb_file|
  require "./#{rb_file}.rb"
end

require 'pry'

class OrderManager
  def price
    @client.prices(instruments: ["USD_JPY"]).get.first
  end
end

class TradeManager
end

@signal        = OrderSignal.new
@order_manager = OrderManager.new
@trade_manager = TradeManager.new

puts @signal.update

# Thread.start do
#   loop do
#     puts @signal.update
#     sleep 0.5
#   end
# end
#
# Thread.start do
#   loop do
#     puts "ask: #{@signal.price.ask}"
#     sleep 1
#   end
# end
#
# sleep 100
