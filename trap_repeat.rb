class TrapRepeatIfDoneAgent

  include Jiji::Model::Agents::Agent

  def self.description
    <<-STR
トラップリピートイフダンのような注文を発行するエージェント(自前)
      STR
  end

  # UIから設定可能なプロパティの一覧
  def self.property_infos
    [
      Property.new('trap_interval_pips', 'トラップを仕掛ける間隔(pips)', 50),
      Property.new('trade_units',        '1注文あたりの取引数量',         1),
      Property.new('profit_pips',        '利益を確定するpips',         100),
      Property.new('slippage',           '許容スリッページ(pips)',       3),
      Property.new('sell_or_buy',        '買注文(buy) or 売注文(sell)', 'buy'),
      Property.new('target_pair',        '通貨ペア',                  'USDJPY'),
      Property.new('stop_loss',          '限界逆指値',                 nil)
    ]
  end

  def post_create
    @trap_repeat_if_done = TrapRepeatIfDone.new(
      target_pair: broker.pairs.find {|p| p.name == @target_pair.to_sym },
      sell_or_buy: @sell_or_buy.to_sym,
      trap_interval_pips: @trap_interval_pips.to_i,
      trade_units: @trade_units.to_i,
      profit_pips: @profit_pips.to_i,
      slippage: @slippage.to_i,
      stop_loss: @stop_loss ? @stop_loss.to_f : nil,
      logger: logger)
  end

  def next_tick(tick)
    @trap_repeat_if_done.register_orders(broker)
  end

  def state
    @trap_repeat_if_done.state
  end

  def restore_state(state)
    @trap_repeat_if_done.restore_state(state)
  end
end

class TrapRepeatIfDone
  def initialize(target_pair: target_pair, sell_or_buy: sell_or_by, trap_interval_pips: trap_interval_pips,
    trade_units: trap_units, profit_pips: profit_pips, slippage: slippage, stop_loss: stop_loss, logger: logger)

    @target_pair        = target_pair
    @trap_interval_pips = trap_interval_pips
    @slippage           = slippage

    @mode = if sell_or_buy == :sell
        Sell.new(target_pair: target_pair, trade_units: trade_units, profit_pips: profit_pips,
          slippage: slippage, stop_loss: stop_loss, logger: logger)
      else
        Buy.new(target_pair: target_pair, trade_units: trade_units, profit_pips: profit_pips,
          slippage: slippage, stop_loss: stop_loss, logger: logger)
      end
    @logger = logger
    @registered_orders   = {}
  end

  # 注文を登録する
  #
  # broker:: broker
  def register_orders(broker)
    broker.instance_variable_get(:@broker).refresh_positions
    # 常に最新の建玉を取得して利用するようにする
    # TODO 公開APIにする

    each_traps(broker.tick) do |trap_open_price|
      next if order_or_position_exists?(trap_open_price, broker)
      register_order(trap_open_price, broker)
    end
  end

  def state
    @registered_orders
  end

  def restore_state(state)
    @registered_orders = state unless state.nil?
  end

  private

  def each_traps(tick)
    current_price = @mode.resolve_current_price(tick[@target_pair.name])
    base = ceil_price(current_price)
    6.times do |n| # baseを基準に、上下3つのトラップを仕掛ける
      trap_open_price = BigDecimal.new(base, 10) \
        + BigDecimal.new(@trap_interval_pips, 10) * (n - 3) * @target_pair.pip
      yield trap_open_price
    end
  end

  # 現在価格をtrap_interval_pipsで丸めた価格を返す。
  #
  #  例) trap_interval_pipsが50の場合、
  #  ceil_price(120.10) # -> 120.00
  #  ceil_price(120.49) # -> 120.00
  #  ceil_price(120.51) # -> 120.50
  #
  def ceil_price(current_price)
    current_price = BigDecimal.new(current_price, 10)
    pip_precision = 1 / @target_pair.pip
    (current_price * pip_precision / @trap_interval_pips ).ceil \
      * @trap_interval_pips / pip_precision
  end

  # trap_open_priceに対応するオーダーを登録する
  def register_order(trap_open_price, broker)
    result = @mode.register_order(trap_open_price, broker)
    unless result.order_opened.nil?
      @registered_orders[key_for(trap_open_price)] = result.order_opened.internal_id
    end
  end

  # trap_open_priceに対応するオーダーを登録済みか評価する
  def order_or_position_exists?(trap_open_price, broker)
    order_exists?(trap_open_price, broker) || position_exists?(trap_open_price, broker)
  end

  def order_exists?(trap_open_price, broker)
    key = key_for(trap_open_price)
    return false unless @registered_orders.include? key
    id = @registered_orders[key]
    order = broker.orders.find {|o| o.internal_id == id }

    !order.nil?
  end

  def position_exists?(trap_open_price, broker)
    # trapのリミット付近でレートが上下して注文が大量に発注されないよう、
    # trapのリミット付近を開始値とする建玉が存在する間は、trapの注文を発行しない
    slipage_price = (@slippage.nil? ? 10 : @slippage) * @target_pair.pip
    position = broker.positions.find do |p|
      # 注文時に指定したpriceちょうどで約定しない場合を考慮して、
      # 指定したslippage(指定なしの場合は10pips)の誤差を考慮して存在判定をする
      p.entry_price < trap_open_price + slipage_price \
      && p.entry_price > trap_open_price - slipage_price
    end

    !position.nil?
  end

  def key_for(trap_open_price)
    (trap_open_price * (1 / @target_pair.pip)).to_i.to_s
  end

  # Super Class of Buy and Sell
  class Mode

    def initialize(target_pair: target_pair, trade_units: trade_units,
      profit_pips: profit_pips, slippage: slippage, stop_loss: stop_loss, logger: logger)
      @target_pair  = target_pair
      @trade_units  = trade_units
      @profit_pips  = profit_pips
      @slippage     = slippage
      @stop_loss    = stop_loss
      @logger       = logger
    end

    # Interface
    # 現在価格を取得する(買の場合Askレート、売の場合Bidレートを使う)
    #
    # tick_value:: 現在の価格を格納するTick::Valueオブジェクト
    # 戻り値:: 現在価格
    def resolve_current_price(tick_value)
    end

    # Interface
    # 注文を登録する
    def register_order(trap_open_price, broker)
    end

    def calculate_price(price, pips)
      price = BigDecimal.new(price, 10)
      pips  = BigDecimal.new(pips,  10) * @target_pair.pip
      (price + pips).to_f
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

  class Sell < Mode
    def resolve_current_price(tick_value)
      tick_value.bid
    end

    def register_order(trap_open_price, broker)
      timestamp = broker.tick.timestamp
      options = create_option(trap_open_price, timestamp)
      print_order_log("sell", options, timestamp)
      broker.sell(@target_pair.name, @trade_units, :marketIfTouched, options)
    end

    def create_option(trap_open_price, timestamp)
      options = {
        price:       trap_open_price.to_f,
        take_profit: calculate_price(trap_open_price, @profit_pips * -1),
        expiry:      timestamp + 60 * 60 * 24 * 7,
        stop_loss:   @stop_loss.nil? ? nil : trap_open_price.to_f + @stop_loss.to_f / 100
      }
      unless @slippage.nil?
        options[:lower_bound] = calculate_price(trap_open_price, @slippage * -1)
        options[:upper_bound] = calculate_price(trap_open_price, @slippage)
      end
      options
    end
  end

  class Buy < Mode
    def resolve_current_price(tick_value)
      tick_value.ask
    end

    def register_order(trap_open_price, broker)
      timestamp = broker.tick.timestamp
      options = create_option(trap_open_price, timestamp)
      print_order_log("buy", options, timestamp)
      broker.buy(@target_pair.name, @trade_units, :marketIfTouched, options)
    end

    def create_option(trap_open_price, timestamp)
      options = {
        price:       trap_open_price.to_f,
        take_profit: calculate_price(trap_open_price, @profit_pips),
        expiry:      timestamp + 60 * 60 * 24 * 7,
        stop_loss:   @stop_loss.nil? ? nil : trap_open_price.to_f - @stop_loss.to_f / 100
      }
      unless @slippage.nil?
        options[:lower_bound] = calculate_price(trap_open_price, @slippage * -1)
        options[:upper_bound] = calculate_price(trap_open_price, @slippage)
      end
      options
    end
  end

end
