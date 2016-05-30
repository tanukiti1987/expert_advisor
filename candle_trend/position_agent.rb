class PositionAgent
  NO_PROFIT_TIPS = 10

  def initialize
    api_client = ApiClient.new
    @client = api_client.client
    @account = api_client.account
  end

  def update
    trade = @account.trades.get.select{|t| t.instrument == "USD_JPY" }.first
    return unless trade
    if trade.side == 'buy'
      if price.bid - trade.price > (NO_PROFIT_TIPS / 1000.0) && trade.stop_loss < trade.price && trade.stop_loss < (price.bid - (NO_PROFIT_TIPS / 1000.0))
        @account.trade(id: trade.id, stop_loss: price.bid - (NO_PROFIT_TIPS / 1000.0)).update
      end
    else
      if trade.price - price.ask > (NO_PROFIT_TIPS / 1000.0) && trade.stop_loss > trade.price && trade.stop_loss > (price.ask + (NO_PROFIT_TIPS / 1000.0))
        @account.trade(id: trade.id, stop_loss: price.ask + (NO_PROFIT_TIPS / 1000.0)).update
      end
    end
  end

  def has_position?
    @account.trades.get.select{|t| t.instrument == "USD_JPY" }.size != 0
  end

  private

  def price
    @client.prices(instruments: ["USD_JPY"]).get.first
  end

  def trades
    @account.trades.get
  end
end
