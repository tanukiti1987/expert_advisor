class OrderAgent
  LAST_ORDERED_DATA_FILE_PATH = 'order_log.json'
  STOP_LOSS_PIPS = 5
  TAKE_PROFIT_PIPS = 10

  POSITION_UNITS = 5_000

  def initialize(position_agent)
    api_client = ApiClient.new
    @client = api_client.client
    @account = api_client.account
    @position_agent = position_agent
  end

  def trade
    if try_order? && !@position_agent.has_position?
      trend = signal_data["trend"]
      side = trend == 'ask' ? 'buy' : 'sell'

      @account.order(
        instrument: "USD_JPY",
        type: "market",
        side: side,
        units: POSITION_UNITS,
        take_profit: take_profit_price(trend),
        stop_loss: stop_loss_price(trend)
      ).create

      save_log(signal_data["signaled_at"])
    end
  rescue OandaAPI::RequestError => e
    nil
  end

  def price
    @client.prices(instruments: ["USD_JPY"]).get.first
  end

  private

  def save_log(signaled_at)
    data = { signaled_at: signaled_at }
    open(LAST_ORDERED_DATA_FILE_PATH, 'w') do |io|
      JSON.dump(data, io)
    end
  end

  def take_profit_price(trend)
    if trend == 'ask'
      price.ask + TAKE_PROFIT_PIPS / 100.0
    elsif trend == 'bid'
      price.bid - TAKE_PROFIT_PIPS / 100.0
    end
  end

  def stop_loss_price(trend)
    if trend == 'ask'
      price.bid - STOP_LOSS_PIPS / 100.0
    elsif trend == 'bid'
      price.ask + STOP_LOSS_PIPS / 100.0
    end
  end

  def signal_data
    open(OrderSignal::RESUTL_FILE_PATH) do |io|
      JSON.load(io)
    end
  end

  def last_ordered_data
    open(LAST_ORDERED_DATA_FILE_PATH) do |io|
      JSON.load(io)
    end
  end

  def try_order?
    signal = signal_data
    last_ordered = last_ordered_data

    signal["trend"] != 'none' &&
      signal["signaled_at"] != last_ordered["signaled_at"]
  end
end
