class PositionAgent
  PRICE_ERROR = 0.008
  TINY_PRICE_ERROR = 0.002
  GRADUAL_PROFIT_TIPS = 0.015

  def initialize
    api_client = ApiClient.new
    @client = api_client.client
    @account = api_client.account
  end

  def update
    trade = target_trade
    return unless trade
    if trade.side == 'buy'
      if bid_price - trade.price > 0 && trade.stop_loss < trade.price
        @account.trade(id: trade.id, stop_loss: trade.price + TINY_PRICE_ERROR).update
      elsif bid_price - trade.stop_loss > GRADUAL_PROFIT_TIPS && trade.stop_loss > trade.price
        @account.trade(id: trade.id, stop_loss: bid_price - GRADUAL_PROFIT_TIPS).update
      end
    else
      if trade.price - ask_price > 0 && trade.stop_loss > trade.price
        @account.trade(id: trade.id, stop_loss: trade.price - TINY_PRICE_ERROR).update
      elsif trade.stop_loss - ask_price > GRADUAL_PROFIT_TIPS && trade.stop_loss < trade.price
        @account.trade(id: trade.id, stop_loss: ask_price + GRADUAL_PROFIT_TIPS).update
      end
    end
  rescue OandaAPI::RequestError => e
    nil
  end

  def has_position?
    target_trade != nil
  end

  private

  def bid_price
    price.bid.round(3) + PRICE_ERROR
  end

  def ask_price
    price.ask.round(3) + PRICE_ERROR
  end

  def price
    @client.prices(instruments: ["USD_JPY"]).get.first
  end

  def target_trade
    @account.trades.get.select{|t| t.instrument == "USD_JPY" }.first
  end
end
