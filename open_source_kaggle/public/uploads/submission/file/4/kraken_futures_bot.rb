#!/usr/bin/env ruby

require "net/http"
require "json"
require "openssl"
require "base64"
require "logger"
require "yaml"
require "csv"
require "optparse"
require "psych"

class Exchange
  def initialize(api_key, api_secret, logger)
    @api_key = api_key
    @api_secret = api_secret
    @logger = logger
  end

  def get_account_balance(symbol)
    raise NotImplementedError, "This method must be implemented by the subclass"
  end

  def get_price(symbol)
    raise NotImplementedError, "This method must be implemented by the subclass"
  end

  def place_order(side, size, price, symbol)
    raise NotImplementedError, "This method must be implemented by the subclass"
  end
end

class KrakenExchange < Exchange
  BASE_URL = "https://api.kraken.com"
  BALANCE_ENDPOINT = "/0/private/Balance"
  TICKER_ENDPOINT = "/0/public/Ticker"
  ORDER_ENDPOINT = "/0/private/AddOrder"

  def get_account_balance(symbol)
    response = api_request("POST", BALANCE_ENDPOINT)
    @logger.debug "kraken | get_account_balance: #{response}"

    if response && response["result"]
      account_info = response["result"]
      currency = symbol.split("/").first
      account_info[currency].to_f
    else
      raise "Failed to get account balance: #{response.inspect}"
    end
  end

  def get_price(symbol)
    @logger.debug "kraken | get_price: #{symbol}"
    response = api_request("GET", "#{TICKER_ENDPOINT}?pair=#{symbol}")
    @logger.debug "kraken | get_price: #{response}"
    if response && response["result"]
      data = response["result"][symbol]
      data["c"][0].to_f
    else
      raise "Failed to get price: #{response.inspect}"
    end
  end

  def place_order(side, size, price, symbol)
    params = {
      ordertype: "limit",
      type: side,
      volume: size,
      pair: symbol,
      price: price,
    }
    response = api_request("POST", ORDER_ENDPOINT, params)
    unless response && response["result"]
      raise "Failed to place order: #{response.inspect}"
    end
  end

  private

  def api_request(method, endpoint, params = {})
    uri = URI("#{BASE_URL}#{endpoint}")
    req = Net::HTTP.const_get(method.capitalize).new(uri)
    req["API-Key"] = @api_key
    req["User-Agent"] = "KrakenSpotBot/1.0"
    if method == "POST"
      nonce = (Time.now.to_f * 1000).to_i.to_s
      params[:nonce] = nonce
      req.set_form_data(params)
      sign_request(req, params)
    end
    send_request(uri, req)
  end

  def sign_request(req, params)
    uri_path = req.path
    post_data = URI.encode_www_form(params)
    message = params[:nonce] + post_data
    sha256 = OpenSSL::Digest::SHA256.digest(message)
    signature = OpenSSL::HMAC.digest("sha512", Base64.decode64(@api_secret), uri_path + sha256)
    req["API-Sign"] = Base64.strict_encode64(signature)
  end

  def send_request(uri, req)
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      response = http.request(req)
      JSON.parse(response.body)
    end
  rescue StandardError => e
    raise "Failed to send request: #{e.message}"
  end
end

class BitmexExchange < Exchange
  BASE_URL = "https://testnet.bitmex.com"
  BALANCE_ENDPOINT = "/api/v1/user/margin"
  TICKER_ENDPOINT = "/api/v1/instrument"
  ORDER_ENDPOINT = "/api/v1/order"

  def get_account_balance(symbol)
    @logger.debug("bitmex | get_account_balance: #{symbol}")

    response = api_request("GET", BALANCE_ENDPOINT)
    @logger.debug("bitmex | get_account_balance: #{response}")
    if response
      response["availableMargin"].to_f / 100000000 # Convert satoshi to BTC
    else
      raise "Failed to get account balance: #{response.inspect}"
    end
  end

  def get_price(symbol)
    @logger.debug "bitmex | get_price: #{symbol}"
    response = api_request("GET", "#{TICKER_ENDPOINT}?symbol=#{symbol}")
    @logger.debug "bitmex | get_price: #{response}"

    if response && !response.empty?
      response[0]["lastPrice"].to_f
    else
      raise "Failed to get price: #{response.inspect}"
    end
  end

  def place_order(side, size, price, symbol)
    params = {
      symbol: symbol,
      side: side.capitalize,
      orderQty: size,
      price: price,
      ordType: "Limit",
    }
    response = api_request("POST", ORDER_ENDPOINT, params)
    unless response
      raise "Failed to place order: #{response.inspect}"
    end
  end

  private

  def api_request(method, endpoint, params = {})
    uri = URI("#{BASE_URL}#{endpoint}")
    req = Net::HTTP.const_get(method.capitalize).new(uri)
    req["api-key"] = @api_key
    nonce = (Time.now.to_f * 1000).to_i.to_s
    req["api-expires"] = nonce

    if method == "POST"
      req.body = params.to_json
      req["Content-Type"] = "application/json"
      req["api-signature"] = generate_signature(method, endpoint, req.body, nonce)
    else
      req["api-signature"] = generate_signature(method, endpoint, URI.encode_www_form(params), nonce)
    end

    @logger.debug "bitmex | api_request: #{uri}, headers: #{req.to_hash}, body: #{req.body}"

    send_request(uri, req)
  end

  def generate_signature(method, endpoint, data, nonce)
    message = "#{method.upcase}#{endpoint}#{nonce}#{data}"
    OpenSSL::HMAC.hexdigest("sha256", @api_secret, message)
  end

  def send_request(uri, req)
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      response = http.request(req)
      JSON.parse(response.body)
    end
  rescue StandardError => e
    raise "Failed to send request: #{e.message}"
  end
end

class TradingBot
  def initialize(config_file: "config.yml", mode:, exchange:, datafile: nil, log_to_stdout: false, starting_balance: nil)
    raise "Configuration file not found." unless File.exist?(config_file)

    config = YAML.load_file(config_file)
    @short_ma_period = config["short_ma_period"]
    @long_ma_period = config["long_ma_period"]
    @rsi_period = config["rsi_period"]
    @atr_period = config["atr_period"]
    @adx_period = config["adx_period"]
    @bollinger_period = config["bollinger_period"]
    @bollinger_stddev = config["bollinger_stddev"]
    @position_scale = config["position_scale"]
    @sleep_interval = config["sleep_interval"]

    @position = 0
    @account_balance = starting_balance
    @logger = Logger.new(log_to_stdout ? STDOUT : "logs/bot.log")
    @logger.level = Logger::DEBUG

    case exchange
    when "kraken"
      @symbol = config["kraken"]["symbol"]
      @exchange = KrakenExchange.new(config["kraken"]["api_key"], config["kraken"]["api_secret"], @logger)
    when "bitmex"
      @symbol = config["bitmex"]["symbol"]
      @exchange = BitmexExchange.new(config["bitmex"]["api_key"], config["bitmex"]["api_secret"], @logger)
    else
      raise "Unsupported exchange: #{exchange}"
    end

    load_state
    initialize_indicators
    setup_signal_handler
    @mode = mode
    @datafile = datafile
    get_account_balance if @mode == "realtime" && @account_balance.nil?
  end

  def run
    case @mode
    when "realtime"
      run_realtime
    when "backtest"
      raise "Datafile must be provided for backtesting" if @datafile.nil?
      run_backtest
    else
      raise "Invalid mode. Use 'realtime' or 'backtest'."
    end
  end

  private

  def initialize_indicators
    @prices = []
    @highs = []
    @lows = []
    @short_prices = []
    @long_prices = []
    @rsi_values = []
    @atr_values = []
    @adx_values = []
    @market_regime = :unknown
    @trades = []
  end

  def setup_signal_handler
    Signal.trap("INT") do
      @logger.info "Received interrupt signal. Saving state and exiting..."
      save_state
      exit
    end
  end

  def load_state
    @logger.debug "Loading state from bot_state.yml"
    if File.exist?("bot_state.yml")
      state = YAML.safe_load(File.read("bot_state.yml"), permitted_classes: [Time, Symbol])
      @prices = state[:prices]
      @highs = state[:highs]
      @lows = state[:lows]
      @short_prices = state[:short_prices]
      @long_prices = state[:long_prices]
      @rsi_values = state[:rsi_values]
      @atr_values = state[:atr_values]
      @adx_values = state[:adx_values]
      @position = state[:position]
      @trades = state[:trades]
      @account_balance = state[:account_balance] || 0
      @logger.info "Loaded previous state"
    else
      initialize_indicators
      @logger.info "No previous state found. Starting fresh."
    end
  end

  def save_state
    @logger.debug "Saving current state to bot_state.yml"
    state = {
      prices: @prices,
      highs: @highs,
      lows: @lows,
      short_prices: @short_prices,
      long_prices: @long_prices,
      rsi_values: @rsi_values,
      atr_values: @atr_values,
      adx_values: @adx_values,
      position: @position,
      trades: @trades,
      account_balance: @account_balance,
    }
    File.write("bot_state.yml", state.to_yaml)
    @logger.info "Saved current state"
  end

  def get_account_balance
    @logger.debug "Getting account balance"
    @account_balance = @exchange.get_account_balance(@symbol)
    @logger.info "Initialized account balance: #{@account_balance}"
  end

  def trade_cycle
    @logger.debug "Starting trade cycle"
    update_price
    if enough_data?
      update_indicators
      detect_market_regime
      make_trading_decision
      manage_open_positions if @mode == "realtime"
    else
      @logger.info "Collecting more data before trading..."
    end
  end

  def enough_data?
    enough = @prices.size >= [@short_ma_period, @long_ma_period, @rsi_period, @atr_period, @adx_period, @bollinger_period].max
    @logger.debug "Checking if enough data: #{enough}"
    enough
  end

  def update_price
    @logger.debug "Updating price for #{@symbol}"
    price = @exchange.get_price(@symbol)
    @logger.debug "Got price: #{price}"
    update_market_data(price, price, price) # Assuming price is the same for high and low in this example
    @logger.info "Current price updated successfully: #{@prices.last}"
  rescue => e
    @logger.error "Exception caught in update_price: #{e.message}"
  end

  def update_market_data(price, high, low)
    @prices << price
    @highs << high
    @lows << low
    manage_ma_prices(@short_prices, @short_ma_period, price)
    manage_ma_prices(@long_prices, @long_ma_period, price)
  end

  def manage_ma_prices(prices, period, price)
    prices << price
    prices.shift if prices.size > period
  end

  def update_indicators
    @logger.debug "Updating indicators"
    update_moving_averages
    update_rsi
    update_atr
    update_adx
    update_bollinger_bands
  end

  def update_moving_averages
    @short_ma = calculate_ma(@short_prices)
    @long_ma = calculate_ma(@long_prices)
    @logger.debug "Updated moving averages: short_ma=#{@short_ma}, long_ma=#{@long_ma}"
  end

  def calculate_ma(prices)
    return nil if prices.empty?
    prices.sum / prices.size.to_f if prices.size.nonzero?
  end

  def update_rsi
    return unless @prices.size > @rsi_period
    gains, losses = calculate_gains_losses
    avg_gain = gains.sum / @rsi_period
    avg_loss = losses.sum / @rsi_period
    rs = avg_loss.zero? ? 100 : avg_gain / avg_loss
    @rsi_values << 100 - (100 / (1 + rs))
    @logger.debug "Updated RSI: #{@rsi_values.last}"
  end

  def calculate_gains_losses
    gains = []
    losses = []
    @prices.each_cons(2) do |prev, curr|
      change = curr - prev
      gains << (change.positive? ? change : 0)
      losses << (change.negative? ? change.abs : 0)
    end
    [gains, losses]
  end

  def update_atr
    return unless @highs.size > @atr_period
    tr = calculate_true_range
    @atr_values << tr.sum / @atr_period
    @logger.debug "Updated ATR: #{@atr_values.last}"
  end

  def calculate_true_range
    @highs.zip(@lows, @prices).each_cons(2).map do |(h1, l1, p1), (h2, l2, p2)|
      [h2 - l2, (h2 - p1).abs, (l2 - p1).abs].max
    end
  end

  def update_adx
    return unless @highs.size > @adx_period
    dx_values = calculate_dx
    @adx_values << (dx_values.sum / @adx_period)
    @logger.debug "Updated ADX: #{@adx_values.last}"
  end

  def calculate_dx
    dx = []
    tr = calculate_true_range
    plus_dm, minus_dm = calculate_plus_minus_dm
    tr.each_with_index do |tr_val, i|
      next if tr_val == 0
      plus_di = 100 * (plus_dm[i] / tr_val)
      minus_di = 100 * (minus_dm[i] / tr_val)
      dx << 100 * (plus_di - minus_di).abs / (plus_di + minus_di)
    end
    dx
  end

  def calculate_plus_minus_dm
    plus_dm = []
    minus_dm = []
    @highs.each_cons(2).zip(@lows.each_cons(2)) do |(h1, h2), (l1, l2)|
      plus_dm << ((h2 - h1) > (l1 - l2) ? [h2 - h1, 0].max : 0)
      minus_dm << ((l1 - l2) > (h2 - h1) ? [l1 - l2, 0].max : 0)
    end
    [plus_dm, minus_dm]
  end

  def update_bollinger_bands
    return unless @prices.size >= @bollinger_period
    ma = calculate_ma(@prices.last(@bollinger_period))
    stddev = Math.sqrt(@prices.last(@bollinger_period).map { |price| (price - ma) ** 2 }.sum / @bollinger_period)
    @upper_band = ma + @bollinger_stddev * stddev
    @lower_band = ma - @bollinger_stddev * stddev
    @logger.debug "Updated Bollinger Bands: upper_band=#{@upper_band}, lower_band=#{@lower_band}"
  end

  def detect_market_regime
    @market_regime = if @adx_values.last && @adx_values.last > 25
        :trending
      elsif @upper_band && @lower_band && @prices.last && ((@upper_band - @lower_band) / @prices.last < 0.03)
        :low_volatility
      else
        :ranging
      end
    @logger.info "Current market regime: #{@market_regime}"
  end

  def make_trading_decision
    return if @account_balance <= 0

    case @market_regime
    when :trending
      trend_following_strategy
    when :ranging
      mean_reversion_strategy
    when :low_volatility
      volatility_breakout_strategy
    end
  end

  def trend_following_strategy
    if @short_ma && @long_ma && @adx_values.last
      if @short_ma > @long_ma && @adx_values.last > 25
        execute_trade("buy") if @position < calculate_position_size
      elsif @short_ma < @long_ma && @adx_values.last > 25
        execute_trade("sell") if @position > -calculate_position_size
      end
    end
  end

  def mean_reversion_strategy
    if @prices.last && @lower_band && @upper_band
      if @prices.last < @lower_band
        execute_trade("buy") if @position < calculate_position_size
      elsif @prices.last > @upper_band
        execute_trade("sell") if @position > -calculate_position_size
      end
    end
  end

  def volatility_breakout_strategy
    if @prices.last && @upper_band && @lower_band
      if @prices.last > @upper_band
        execute_trade("buy") if @position < calculate_position_size
      elsif @prices.last < @lower_band
        execute_trade("sell") if @position > -calculate_position_size
      end
    end
  end

  def execute_trade(side)
    size = calculate_position_size
    trade_cost = size * @prices.last

    if trade_cost > @account_balance && side == "buy"
      @logger.warn "Insufficient balance for trade. Current balance: #{@account_balance}, required: #{trade_cost}"
      return
    end

    if @mode == "realtime"
      @exchange.place_order(side, size, @prices.last, @symbol)
    else
      simulate_trade(side, size)
    end

    @position += (side == "buy" ? size : -size)
    trade = { side: side, size: size, price: @prices.last, time: Time.now }
    @trades << trade
    @logger.info "Executed trade: #{trade}"
  end

  def calculate_position_size
    return 0 if @prices.last.nil? || @atr_values.last.nil?

    current_price = @prices.last
    volatility = @atr_values.last / current_price
    momentum = (@short_ma - @long_ma) / @long_ma

    @logger.debug "Calculating position size: current_price=#{current_price}, volatility=#{volatility}, momentum=#{momentum}"

    # Calculate position sizes based on volatility and momentum
    volatility_based_size = @account_balance * (1.0 / volatility)
    momentum_based_size = @account_balance * [momentum, 0.1].max

    @logger.debug "Position sizes: volatility_based_size=#{volatility_based_size}, momentum_based_size=#{momentum_based_size}"

    # Combine the two strategies
    combined_size = (volatility_based_size + momentum_based_size) / 2.0

    # Ensure position size does not exceed 10% of the account balance
    max_size = @account_balance * 0.10
    final_size = [combined_size, max_size]

    # Ensure total trade size does not exceed 20% of the account balance
    max_trade_size = (@account_balance * 0.20) / current_price
    final_trade_size = [final_size, max_trade_size]

    @logger.info "Calculated position size: #{final_trade_size} based on volatility: #{volatility}, momentum: #{momentum}, combined: #{combined_size}, price: #{current_price}"

    final_trade_size
  end

  def manage_open_positions
    get_account_balance if @mode == "realtime"
  end

  def simulate_trade(side, size)
    price = @prices.last
    trade_cost = size * price
    if side == "buy"
      @account_balance -= trade_cost
      @account_balance = 0 if @account_balance.negative?
    else
      @account_balance += trade_cost
    end
    @logger.info "Simulated trade: #{side} #{size} at #{price}, new balance: #{@account_balance}"
  end

  def run_realtime
    loop do
      trade_cycle
      save_state
      sleep @sleep_interval
    end
  end

  def run_backtest
    CSV.foreach(@datafile, headers: true) do |row|
      update_market_data(row["price"].to_f, row["high"].to_f, row["low"].to_f)
      if enough_data?
        update_indicators
        detect_market_regime
        make_trading_decision
        @logger.info "Account Balance: #{@account_balance}"
        break if @account_balance <= 0
      end
    end
    print_backtest_summary
  end

  def print_backtest_summary
    total_trades = @trades.size
    total_profit = @account_balance - 10000
    @logger.info "Backtest Summary:"
    @logger.info "Total Trades Executed: #{total_trades}"
    @logger.info "Total Profit: #{total_profit.round(2)}"
    @logger.info "Final Account Balance: #{@account_balance.round(2)}"
  end
end

if __FILE__ == $0
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: trading_bot.rb [options]"
    opts.on("-m", "--mode MODE", "Mode: 'realtime' or 'backtest'") { |v| options[:mode] = v }
    opts.on("-e", "--exchange EXCHANGE", "Exchange: 'kraken' or 'bitmex'") { |v| options[:exchange] = v }
    opts.on("-d", "--datafile DATAFILE", "Historical data file for backtesting") { |v| options[:datafile] = v }
    opts.on("-l", "--log_to_stdout", "Log to STDOUT instead of a file") { |v| options[:log_to_stdout] = v }
    opts.on("-b", "--balance BALANCE", "Starting balance for backtesting") { |v| options[:balance] = v.to_f }
  end.parse!

  if options.empty? || !options[:mode] || !options[:exchange]
    puts "Error: No options provided. Usage: trading_bot.rb [options]"
    puts "Options:"
    puts "  -m, --mode MODE           Mode: 'realtime' or 'backtest'"
    puts "  -e, --exchange EXCHANGE   Exchange: 'kraken' or 'bitmex'"
    puts "  -d, --datafile DATAFILE   Historical data file for backtesting"
    puts "  -l, --log_to_stdout       Log to STDOUT instead of a file"
    puts "  -b, --balance BALANCE     Starting balance for backtesting"
    exit
  end

  mode = options[:mode]
  exchange = options[:exchange]
  datafile = options[:datafile]
  log_to_stdout = options[:log_to_stdout] || false
  balance = options[:balance] || (mode == "realtime" ? nil : 10000)

  bot = TradingBot.new(config_file: "config.yml", mode: mode, exchange: exchange, datafile: datafile, log_to_stdout: log_to_stdout, starting_balance: balance)
  bot.run
end
