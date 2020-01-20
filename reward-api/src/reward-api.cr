require "csv"
require "http/client"
require "file_utils"
require "json"
require "./bech32"

module JormungandrApi
  REST_API_URL = ENV["JORMUNGANDR_RESTAPI_URL"]? || "http://127.0.0.1:3101/api"
  GRAPHQL_URL  = ENV["JORMUNGANDR_GRAPHQL_URL"]? || "http://127.0.0.1:3101/explorer/graphql"

  def self.get(endpoint)
    url = REST_API_URL + "/v0" + endpoint

    HTTP::Client.get(url) do |response|
      case response.status
      when HTTP::Status::OK
        response.body_io.gets_to_end
      else
        raise "Error querying #{url}: #{response.inspect}"
      end
    end
  end

  def self.graphql(**payload)
    HTTP::Client.post(**graphql_args(payload)) do |response|
      if response.status == HTTP::Status::OK
        JSON.parse(response.body_io.gets_to_end)
      else
        pp! response
        raise response.body_io.gets_to_end
      end
    end
  end

  private def self.graphql_args(payload)
    {
      url:     GRAPHQL_URL,
      body:    payload.to_json,
      headers: HTTP::Headers{
        "Content-Type" => "application/json",
      },
    }
  end
end

module Rewards
  REWARD_DIRECTORY       = ENV["JORMUNGANDR_REWARD_DUMP_DIRECTORY"]? || File.expand_path("rewards")
  BLOCK_CACHE_DIRECTORY  = File.join(REWARD_DIRECTORY, "block-cache")
  REWARD_CACHE_DIRECTORY = File.join(REWARD_DIRECTORY, "reward-cache")
  FileUtils.mkdir_p(BLOCK_CACHE_DIRECTORY)
  FileUtils.mkdir_p(REWARD_CACHE_DIRECTORY)

  class Block
    GENESIS                   = "0000000000000000000000000000000000000000000000000000000000000000"
    LAST_BLOCK_OF_EPOCH_QUERY = <<-GRAPHQL
      query GetLastBlockOfEpoch($id: EpochNumber!){
        epoch(id: $id) {
          lastBlock {
            id
          }
        }
      }
    GRAPHQL

    getter id : String
    getter content : String

    def self.tip
      new JormungandrApi.get("/tip")
    end

    def self.last_block_of_epoch(epoch)
      result = JormungandrApi.graphql(
        operationName: "GetLastBlockOfEpoch",
        variables: {id: epoch.to_s},
        query: LAST_BLOCK_OF_EPOCH_QUERY,
      )

      last_block_id = result.dig?("data", "epoch", "lastBlock", "id").try(&.as_s) rescue nil
      new last_block_id if last_block_id
    end

    def initialize(@id)
      raise "Invalid id: '#{@id}'" unless id.size == 64
      @content = fetch_block_content
      raise "Content too short: #{content.size}" unless content.size >= 232
    end

    def last_block_of_epoch
      self.class.last_block_of_epoch(epoch)
    end

    def epoch
      content[16...24].to_i(16)
    end

    def slot
      content[24...32].to_i(16)
    end

    def height
      content[32...40].to_i(16)
    end

    def parent_id
      content[104...168]
    end

    def parent
      self.class.new parent_id unless parent_id == GENESIS
    end

    def pool
      content[168...232]
    end

    def each_block_until_beginning_of_epoch
      current = self
      until !current || current.epoch != epoch
        if current
          yield current
          current = current.parent
        else
          return
        end
      end
    end

    def fetch_block_content
      if File.file?(block_cache_path) && File.size(block_cache_path) > 231
        File.open(block_cache_path) do |io|
          slice = Bytes.new(232)
          io.read_fully(slice)
          slice.hexstring
        end
      else
        JormungandrApi.get("/block/#{@id}").tap { |block|
          File.write(block_cache_path, block)
        }.to_slice.hexstring
      end
    end

    private def block_cache_path
      File.join(BLOCK_CACHE_DIRECTORY, @id)
    end

    private def rewards_csv_path
      File.join REWARD_DIRECTORY, "reward-info-#{epoch + 1}-#{@id}"
    end

    private def rewards_cache_path
      File.join REWARD_CACHE_DIRECTORY, "#{@id}.json"
    end

    def read_csv
      dest = rewards_cache_path
      if File.file?(dest) && File.size(dest) > 0
        return File.open(dest) { |io| Epoch.from_json(io) }
      end

      accounts = Hash(String, Int64).new
      pools = Hash(String, Pool).new
      treasury = 0_i64
      fees = 0_i64
      drawn = 0_i64

      File.open(rewards_csv_path) do |io|
        csv = CSV.new(io, headers: true)

        while csv.next
          row = csv.row.to_h

          case row["type"]
          when "account"
            addr = Bech32.convert_hex_pub_key(row["identifier"])
            accounts[addr] = row["received"].to_i64
          when "pool"
            addr = row["identifier"]
            pools[addr] = Pool.new(row["received"].to_i64, row["distributed"].to_i64)
          when "drawn"
            drawn = row["distributed"].to_i64
          when "treasury"
            treasury = row["received"].to_i64
          when "fees"
            fees = row["distributed"].to_i64
          else
            puts "unknown type: '#{row["type"]}'"
          end
        end
      end

      Epoch.new(accounts, pools, treasury, fees, drawn).tap do |epoch|
        File.write(dest, epoch.to_pretty_json)
      end
    end
  end

  class Epoch
    JSON.mapping(
      accounts: Hash(String, Int64),
      pools: Hash(String, Pool),
      treasury: Int64,
      fees: Int64,
      drawn: Int64
    )

    def initialize(@accounts, @pools, @treasury, @fees, @drawn)
    end
  end

  record Account, identifier : String, received : Int64 do
    def to_json(io)
      {identifier: identifier, received: received}.to_json(io)
    end
  end

  class Pool
    JSON.mapping(
      received: Int64,
      distributed: Int64,
      block_ids: Set(String)?,
    )

    def initialize(@received, @distributed)
    end

    def to_json(io)
      {received: received, distributed: distributed, block_count: block_count}.to_json(io)
    end

    def block_count
      if ids = block_ids
        ids.size
      else
        0
      end
    end

    def add_block_id(block_id)
      ids = @block_ids || Set(String).new
      ids << block_id
      @block_ids = ids
    end
  end
end

require "kemal"

get "/api/rewards/warmup" do
  epochs = (0...Rewards::Block.tip.epoch)
  total = epochs.size
  done = Channel(Int32).new

  epochs.each do |epoch|
    spawn do
      next unless block = Rewards::Block.last_block_of_epoch(epoch)
      block.each_block_until_beginning_of_epoch { |_| }
      done.send epoch
    end
  end

  total.times do |i|
    epoch = done.receive
    puts "Finished fetching epoch %04d %04d/%04d" % [epoch, i + 1, total]
  end
end

get "/api/rewards/epoch/:epoch" do |env|
  epoch = env.params.url["epoch"].to_i32

  if block = Rewards::Block.last_block_of_epoch(epoch)
    result = block.read_csv
    block.each_block_until_beginning_of_epoch do |block_in_epoch|
      next unless pool = result.pools[block_in_epoch.pool]?
      pool.add_block_id block_in_epoch.id
    end
    result.to_pretty_json
  else
    {error: "Not Found"}
  end
end

get "/api/rewards/total" do
  fees = treasury = drawn = 0_u64
  accounts = Hash(String, Int64).new
  pool_totals = Hash(String, Rewards::Pool).new

  (0...Rewards::Block.tip.epoch).each do |epoch|
    next unless block = Rewards::Block.last_block_of_epoch(epoch)
    next unless result = block.read_csv

    fees += result.fees
    treasury += result.treasury
    drawn += result.drawn

    result.accounts.each do |addr, amount|
      account = accounts[addr]? || 0_i64
      accounts[addr] = account + amount
    end

    result.pools.each do |pool_id, pool|
      pool_total = pool_totals[pool_id]? || Rewards::Pool.new(0_i64, 0_i64)
      pool_total.distributed += pool.distributed
      pool_total.received += pool.received
      pool_totals[pool_id] = pool_total
    end

    block.each_block_until_beginning_of_epoch do |block_in_epoch|
      pool_total = pool_totals[block_in_epoch.pool]? || Rewards::Pool.new(0_i64, 0_i64)
      pool_total.add_block_id block_in_epoch.id
      pool_totals[block_in_epoch.pool] = pool_total
    end
  end

  {
    fees:     fees,
    treasury: treasury,
    drawn:    drawn,
    pools:    pool_totals,
    accounts: accounts,
  }.to_pretty_json
end

get "/api/rewards/account/:pubkey" do |env|
  pubkey = env.params.url["pubkey"]

  epochs = Hash(String, Int64).new

  (0...Rewards::Block.tip.epoch).each do |epoch|
    next unless block = Rewards::Block.last_block_of_epoch(epoch)
    next unless result = block.read_csv
    next unless received = result.accounts[pubkey]?
    epochs[block.epoch.to_s] = received
  end

  {total: epochs.values.sum, epochs: epochs}.to_pretty_json
end

get "/api/rewards/pool/:poolid" do |env|
  pool_id = env.params.url["poolid"]

  epochs = Hash(String, Rewards::Pool).new

  (0...Rewards::Block.tip.epoch).each do |epoch|
    next unless block = Rewards::Block.last_block_of_epoch(epoch)
    next unless result = block.read_csv
    block.each_block_until_beginning_of_epoch do |block_in_epoch|
      next unless block_in_epoch.pool == pool_id
      result.pools[block_in_epoch.pool].add_block_id block_in_epoch.id
    end

    next unless pool = result.pools[pool_id]?
    epochs[block.epoch.to_s] = pool
  end

  {
    total: {
      block_count: epochs.values.map(&.block_count).sum,
      distributed: epochs.values.map(&.distributed).sum,
      received:    epochs.values.map(&.received).sum,
    },
    epochs: epochs,
  }.to_pretty_json
end

Kemal.run
