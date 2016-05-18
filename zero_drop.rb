class ZeroDropAgent

  include Jiji::Model::Agents::Agent

  def self.description
    <<-STR
同値撤退を務めるエージェント
      STR
  end

  # UIから設定可能なプロパティの一覧
  def self.property_infos
    [
      Property.new('trade_unit',  '1注文あたりの取引数量', 5000),
      Property.new('slippage',    '許容スリッページ(pips)', 3),
      Property.new('stop_loss',   '逆指値', 15),
      Property.new('target_pair', '通貨ペア', 'USDJPY'),
      Property.new('start_type',  'トレード初め(buy/sell)', 'buy'),
      Property.new('take_profit', '利益を取り始めるpips', 3),
      Property.new('trend_trade', 'n回まで同じ方法でトレード', 3)
    ]
  end

  def post_create
    @zero_drop = ZeroDrop.new(
      target_pair: broker.pairs.find {|p| p.name == @target_pair.to_sym },
      trade_unit: @trade_unit.to_i,
      slippage: @slippage.to_i,
      stop_loss: @stop_loss.to_i,
      start_type: @start_type.to_sym,
      trend_trade: @trend_trade.to_i,
      take_profit: @take_profit.to_i,
      logger: logger)
  end

  def next_tick(tick)
    @zero_drop.register_order(broker)
  end

  def state
    @zero_drop.state
  end

  def restore_state(state)
    @zero_drop.restore_state(state)
  end
end

class ZeroDrop
  def initialize(target_pair: target_pair, trade_unit: trap_units,
    slippage: slippage, stop_loss: stop_loss, start_type: start_type,
    trend_trade: trend_trade, take_profit: take_profit, logger: logger)

    @target_pair = target_pair
    @trade_unit  = trade_unit
    @slippage    = slippage.to_f
    @stop_loss = stop_loss.to_f
    @logger = logger
    @trade_type = start_type
    @trend_trade = trend_trade
    @take_profit = take_profit.to_f
  end

  ## 注文を出すところ
  def register_order(broker)
    broker.instance_variable_get(:@broker).refresh_positions

    if position = current_position(broker)
      # 利益を出した場合に損切りレートを更新
      @logger.info "===== take_profit: #{@take_profit} current: #{profit_or_loss_pips(position)} ======"
      if @take_profit > profit_or_loss_pips(position) && profit_or_loss_pips(position) >= 2.0 &&
        loss_stop_loss_position?(position)
        position.closing_policy.stop_loss != zero_profit_stop_loss(position)
        position.closing_policy = Jiji::Model::Trading::ClosingPolicy.create({
          stop_loss: zero_profit_stop_loss(position)
        })
        @logger.info "[#{broker.tick.timestamp}(#{position.sell_or_buy == :buy ? broker.tick[@target_pair.name].bid : broker.tick[@target_pair.name].ask})] UPDATE_1: #{position.sell_or_buy} stop_loss #{position.closing_policy.stop_loss} ---> #{zero_profit_stop_loss(position)}"
        position.modify
      elsif profit_or_loss_pips(position) >= @take_profit && should_change_stop_loss?(broker, position)
        position.closing_policy = Jiji::Model::Trading::ClosingPolicy.create({
          stop_loss: new_profit_stop_loss(broker.tick[@target_pair.name])
        })
        @logger.info "[#{broker.tick.timestamp}(#{position.sell_or_buy == :buy ? broker.tick[@target_pair.name].bid : broker.tick[@target_pair.name].ask})] UPDATE_2: #{position.sell_or_buy} stop_loss #{position.closing_policy.stop_loss} ---> #{new_profit_stop_loss(broker.tick[@target_pair.name])}"
        position.modify
      end
    else
      update_trade_type(broker)

      if buy_mode?
        options = {
          stop_loss: calc_tick(broker.tick[@target_pair.name].ask, @stop_loss * -1),
          upper_bound: calc_tick(broker.tick[@target_pair.name].ask, @slippage),
        }
        broker.buy(@target_pair.name, @trade_unit, :market, options)
        @logger.info "[#{broker.tick.timestamp}] BUY: #{broker.tick[@target_pair.name].ask} stop_loss: #{calc_tick(broker.tick[@target_pair.name].ask, @stop_loss * -1)}, upper_bound: #{calc_tick(broker.tick[@target_pair.name].ask, @slippage)}"
      else
        options = {
          stop_loss: calc_tick(broker.tick[@target_pair.name].bid, @stop_loss),
          lower_bound: calc_tick(broker.tick[@target_pair.name].bid, @slippage * -1),
        }
        broker.sell(@target_pair.name, @trade_unit, :market, options)
        @logger.info "[#{broker.tick.timestamp}] SELL: #{broker.tick[@target_pair.name].bid} stop_loss: #{calc_tick(broker.tick[@target_pair.name].bid, @stop_loss)}, lower_bound: #{calc_tick(broker.tick[@target_pair.name].bid, @slippage * -1)}"
      end
    end
  end

  def state
  end

  def restore_state(state)
  end

  private

  def calc_tick(current_price, pips)
    current_price.to_f + (pips / 100.0)
  end

  def current_position(broker)
    broker.positions.select {|position| position.status == :live }.first
  end

  def buy_mode?
    @trade_type == :buy
  end

  def reverse_trade_type!
    @trade_type = buy_mode? ? :sell : :buy
  end

  def update_trade_type(broker)
    closed_positions = broker.load_positions.select {|position| position.status == :closed }
    closed_positions = closed_positions.sort_by {|position| position.exited_at }.reverse.first(@trend_trade)

    if !closed_positions.empty? && closed_positions.all? {|position| position.profit_or_loss < 0 }
      reverse_trade_type!
    end
  end

  def loss_stop_loss_position?(position)
    if buy_mode?
      position.entry_price > position.closing_policy.stop_loss
    else
      position.entry_price < position.closing_policy.stop_loss
    end
  end

  # 現在獲得しているpips
  def profit_or_loss_pips(position)
    (position.profit_or_loss / position.units.to_f) * 100
  end

  ## 購入価格をストップロスとして返却
  def zero_profit_stop_loss(position)
    @logger.info "entry_price: #{position.entry_price} stop_loss: #{position.closing_policy.stop_loss}"
    buy_mode? ? calc_tick(position.entry_price, 1.0) : calc_tick(position.entry_price, -1.0)
  end

  def should_change_stop_loss?(broker, position)
    if buy_mode?
      new_profit_stop_loss(broker.tick[@target_pair.name]) > position.closing_policy.stop_loss
    else
      new_profit_stop_loss(broker.tick[@target_pair.name]) < position.closing_policy.stop_loss
    end
  end

  # 新しい損切りレートを計算
  def new_profit_stop_loss(tick)
    if buy_mode?
      @logger.info "bid: #{tick.bid} take_profit: #{@take_profit}"
      tick.bid - (@take_profit / 100)
    else
      @logger.info "ask: #{tick.ask} take_profit: #{@take_profit}"
      tick.ask + (@take_profit / 100)
    end
  end
end
