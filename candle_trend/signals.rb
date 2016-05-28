class OrderSignal
  ENOUGH_PRICE_MOVEMENT = 0.01
  REFERAL_CANDLES_NUM   = 3
  RESUTL_FILE_PATH      = 'signal.json'

  def initialize
    @candles = Candle.new
  end

  def update
    trend_data = analyze(@candles.latest)
    return unless trend_data

    open(RESUTL_FILE_PATH, 'w') do |io|
      JSON.dump(trend_data, io)
    end
  end

  private

  def analyze(candles)
    return if candles.size < REFERAL_CANDLES_NUM
    calndes = trim_completed(candles)

    trend =
      if candles.all? {|c| bid_ask_trend(c) == :ask }
        'ask'
      elsif candles.all? {|c| bid_ask_trend(c) == :bid }
        'bid'
      else
        'none'
      end

    { trend: trend, signaled_at: candles.last.time }
  end

  def trim_completed(candles)
    canldes.select {|c| c.complete? }.last(REFERAL_CANDLES_NUM)
  end

  def bid_ask_trend(candle)
    return :none unless enough_price_movement?(candle)

    if candle.open_mid > candle.close_mid
      :bid
    elsif candle.open_mid < candle.close_mid
      :ask
    else
      :none
    end
  end

  def enough_price_movement?(candle)
    (candle.open_mid - candle.close_mid).abs >= ENOUGH_PRICE_MOVEMENT
  end
end
