class ApiClient
  DEMO_ACCOUNT_ID = ENV.fetch("OANDA_DEMO_ACCOUNT_ID")

  attr_reader :client

  def initialize(demo: true)
    if demo == true
      @client = OandaAPI::Client::TokenClient.new(:practice, ENV.fetch("OANDA_DEMO_API_KEY"))
      @account_id = DEMO_ACCOUNT_ID
    else
      # implement later
    end
  end

  def account
    @account ||= @client.account(@account_id)
  end
end
