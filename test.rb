class TestAgent

  include Jiji::Model::Agents::Agent

  def self.description
    <<-STR
テストエージェント
      STR
  end

  def post_create
    @test = Test.new(
      target_pair: 'USDJPY',
      logger: logger)
  end

  def next_tick(tick)
    @test.register_order(broker)
  end

  def state
  end

  def restore_state(state)
  end
end

class Test
  def initialize(target_pair: target_pair, logger: logger)
    @target_pair = target_pair
    @logger = logger
  end

  def register_order(broker)
    broker.instance_variable_get(:@broker).refresh_positions
    @logger.info "[#{broker.tick.timestamp}] #{broker.tick[@target_pair.name].ask}"
  end
end
