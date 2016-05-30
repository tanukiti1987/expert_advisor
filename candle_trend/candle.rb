class Candle
  attr_reader :instrument, :granularity, :time

  DEFAULT_LENGTH_OF_TIME = 3.minutes

  def initialize(instrument: 'USD_JPY', granularity: 'M1', time: DEFAULT_LENGTH_OF_TIME)
    @instrument = instrument
    @granularity = granularity
    @time = time
    @client = ApiClient.new.client
  end

  def latest
    @client.candles(instrument: instrument,
                   granularity: granularity,
                 candle_format: "midpoint",
                         start: starts_at).get
  end

  private

  def starts_at
    (Time.now - time).utc.to_datetime.rfc3339
  end
end
