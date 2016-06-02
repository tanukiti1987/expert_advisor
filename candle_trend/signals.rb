class OrderSignal
  ENOUGH_PRICE_MOVEMENT = 0.03
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

    candles = trim_completed(candles)
    trend =
      if candles.all? {|c| ask_candle?(c) } && candle_length(candles) > ENOUGH_PRICE_MOVEMENT
        'bid'
      elsif candles.all? {|c| bid_candle?(c) } && candle_length(candles) > ENOUGH_PRICE_MOVEMENT
        'ask'
      else
        'none'
      end

    { trend: trend, signaled_at: candles.last.time }
  end

  def trim_completed(candles)
    candles.select {|c| c.complete? }.last(REFERAL_CANDLES_NUM)
  end

  def bid_candle?(candle)
    candle.open_mid > candle.close_mid
  end

  def ask_candle?(candle)
    candle.open_mid < candle.close_mid
  end

  def candle_length(candles)
    candles.inject(0.0) {|sum, c| sum + (c.open_mid - c.close_mid).abs }
  end

  def enough_price_movement?(candle)
    (candle.open_mid - candle.close_mid).abs >= ENOUGH_PRICE_MOVEMENT
  end
end
