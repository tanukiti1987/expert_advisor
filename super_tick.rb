class SuperTickAgent

  include Jiji::Model::Agents::Agent

  def self.description
    <<-STR
急なトレンドの時にトレール注文を入れるヤツ
      STR
  end

  # UIから設定可能なプロパティの一覧
  def self.property_infos
    [
      Property.new('min_trend_threshold',    '最小トレンド傾斜', 0.65),
      Property.new('max_trend_threshold',    '最大トレンド傾斜', 1.2),
      Property.new('trade_unit',        '1注文あたりの取引数量', 5000),
      Property.new('trailing_stop',      'トレールストップ', 30),
      Property.new('profit_pips',        '利益を確定するpips', 100),
      Property.new('slippage',           '許容スリッページ(pips)', 3),
      Property.new('target_pair',        '通貨ペア', 'USDJPY'),
    ]
  end

  def post_create
    @super_tick = SuperTick.new(
      target_pair: broker.pairs.find {|p| p.name == @target_pair.to_sym },
      trade_unit: @trade_unit.to_i,
      profit_pips: @profit_pips.to_i,
      slippage: @slippage.to_i,
      min_trend_threshold: @min_trend_threshold.to_f,
      max_trend_threshold: @max_trend_threshold.to_f,
      trailing_stop: @trailing_stop.to_i,
      logger: logger)
  end

  def next_tick(tick)
    @super_tick.register_order(broker)
  end

  def state
    @super_tick.state
  end

  def restore_state(state)
    @super_tick.restore_state(state)
  end
end

class SuperTick
  def initialize(target_pair: target_pair, trade_unit: trap_units,
    profit_pips: profit_pips, slippage: slippage, min_trend_threshold: min_trend_threshold,
    max_trend_threshold: max_trend_threshold, trailing_stop: trailing_stop, logger: logger)

    @target_pair = target_pair
    @trade_unit  = trade_unit
    @profit_pips = profit_pips
    @slippage    = slippage
    @min_trend_threshold = min_trend_threshold
    @max_trend_threshold = max_trend_threshold
    @trailing_stop = trailing_stop
    @logger = logger

    @last_order_time = nil
    @old_tick = nil
  end

  def register_order(broker)
    broker.instance_variable_get(:@broker).refresh_positions

    if @old_tick
      if bid_trend(broker.tick, @old_tick) > @min_trend_threshold && bid_trend(broker.tick, @old_tick) < @max_trend_threshold && broker.tick.timestamp - @last_order_time > 360
        timestamp = broker.tick.timestamp
        options = {
          price: calc_tick(broker.tick[@target_pair.name].bid, 10),
          expiry: timestamp + 60 * 3,
          take_profit: calc_tick(broker.tick[@target_pair.name].bid, @profit_pips * -1),
          trailing_stop: @trailing_stop,
          lower_bound: calc_tick(broker.tick[@target_pair.name].bid, @slippage * -1),
        }
        @logger.info "bid: #{bid_trend(broker.tick, @old_tick)}"
        @logger.info "ask: #{ask_trend(broker.tick, @old_tick)}"
        print_order_log("sell", options, timestamp)
        broker.sell(@target_pair.name, @trade_unit, :marketIfTouched, options)

        @last_order_time = broker.tick.timestamp
      end

      if ask_trend(broker.tick, @old_tick) > @min_trend_threshold && ask_trend(broker.tick, @old_tick) < @max_trend_threshold && broker.tick.timestamp - @last_order_time > 360
        timestamp = broker.tick.timestamp
        options = {
          price: calc_tick(broker.tick[@target_pair.name].ask, -10),
          expiry: timestamp + 60 * 3,
          take_profit: calc_tick(broker.tick[@target_pair.name].ask, @profit_pips),
          trailing_stop: @trailing_stop,
          upper_bound: calc_tick(broker.tick[@target_pair.name].ask, @slippage),
        }

        @logger.info "bid: #{bid_trend(broker.tick, @old_tick)}"
        @logger.info "ask: #{ask_trend(broker.tick, @old_tick)}"
        print_order_log("buy", options, timestamp)
        broker.buy(@target_pair.name, @trade_unit, :marketIfTouched, options)

        @last_order_time = broker.tick.timestamp
      end
    else
      @last_order_time = broker.tick.timestamp
    end

    @old_tick = broker.tick
  end

  def state
    { last_order_time: @last_order_time, old_tick: @old_tick }
  end

  def restore_state(state)
    @last_order_time = state[:last_order_time] if state && state[:last_order_time]
    @old_tick = state[:old_tick] if state && state[:old_tick]
  end

  private

  def bid_trend(current_tick, old_tick)
    ((old_tick[@target_pair.name].bid - current_tick[@target_pair.name].bid).to_f * 100.0) / (current_tick.timestamp - old_tick.timestamp).to_f
  end

  def ask_trend(current_tick, old_tick)
    ((current_tick[@target_pair.name].ask - old_tick[@target_pair.name].ask).to_f * 100.0) / (current_tick.timestamp - old_tick.timestamp).to_f
  end

  def calc_tick(current_price, pips)
    current_price.to_f + (pips / 100.0)
  end

  def print_order_log(mode, options, timestamp)
    return unless @logger
    message = [
      mode, timestamp, options[:price], options[:take_profit],
      options[:lower_bound], options[:upper_bound]
    ].map {|item| item.to_s }.join(" ")
    @logger.info message
  end
end
