import {
  CronCapability,
  HTTPClient,
  handler,
  Runner,
  type NodeRuntime,
  type Runtime,
} from "@chainlink/cre-sdk";

type Config = {
  schedule: string;
  apiUrl: string;
  symbol: string;
};

interface OrderBook {
  lastUpdateId: number;
  bids: [string, string][];
  asks: [string, string][];
}

interface LiquidityMetrics {
  timestamp: number;
  symbol: string;
  midPrice: number;
  spread: number;
  spreadBps: number;
  totalBidLiquidity: string;
  totalAskLiquidity: string;
  totalBidLiquidityETH: number;
  totalAskLiquidityETH: number;
  bidLevels: number;
  askLevels: number;
  liquidity1PercentDepth: {
    bids: number;
    asks: number;
  };
  liquidity5PercentDepth: {
    bids: number;
    asks: number;
  };
}

function weiToEth(wei: string): number {
  return Number(wei) / 1e18;
}

function calculateTotalLiquidity(levels: [string, string][]): { total: string; totalETH: number } {
  let total = BigInt(0);
  for (const [, quantity] of levels) {
    total += BigInt(quantity);
  }
  return {
    total: total.toString(),
    totalETH: weiToEth(total.toString())
  };
}

function calculateDepthLiquidity(
  levels: [string, string][],
  midPrice: number,
  percentDepth: number,
  isBid: boolean
): number {
  let totalLiquidity = BigInt(0);
  const threshold = isBid
    ? midPrice * (1 - percentDepth / 100)
    : midPrice * (1 + percentDepth / 100);

  for (const [priceStr, quantityStr] of levels) {
    const price = Number(priceStr);
    if (isBid ? price >= threshold : price <= threshold) {
      totalLiquidity += BigInt(quantityStr);
    }
  }

  return weiToEth(totalLiquidity.toString());
}

function calculateLiquidityMetrics(orderBook: OrderBook, symbol: string): LiquidityMetrics {
  const { bids, asks } = orderBook;

  if (bids.length === 0 || asks.length === 0) {
    throw new Error('Order book has no bids or asks');
  }

  const bestBid = Number(bids[0][0]);
  const bestAsk = Number(asks[0][0]);
  const midPrice = (bestBid + bestAsk) / 2;
  const spread = bestAsk - bestBid;
  const spreadBps = (spread / midPrice) * 10000;

  const bidLiquidity = calculateTotalLiquidity(bids);
  const askLiquidity = calculateTotalLiquidity(asks);

  const liquidity1Percent = {
    bids: calculateDepthLiquidity(bids, midPrice, 1, true),
    asks: calculateDepthLiquidity(asks, midPrice, 1, false)
  };

  const liquidity5Percent = {
    bids: calculateDepthLiquidity(bids, midPrice, 5, true),
    asks: calculateDepthLiquidity(asks, midPrice, 5, false)
  };

  return {
    timestamp: Date.now(),
    symbol,
    midPrice,
    spread,
    spreadBps,
    totalBidLiquidity: bidLiquidity.total,
    totalAskLiquidity: askLiquidity.total,
    totalBidLiquidityETH: bidLiquidity.totalETH,
    totalAskLiquidityETH: askLiquidity.totalETH,
    bidLevels: bids.length,
    askLevels: asks.length,
    liquidity1PercentDepth: liquidity1Percent,
    liquidity5PercentDepth: liquidity5Percent
  };
}

function toFixed(num: number, decimals: number): string {
  const factor = Math.pow(10, decimals);
  return String(Math.round(num * factor) / factor);
}

/**
 * Fetch order book - executed by each node in the DON
 * This is the "map" function in the map-reduce pattern
 */
const fetchOrderBook = (nodeRuntime: NodeRuntime<Config>): OrderBook => {
  const httpClient = new HTTPClient();

  const url = `${nodeRuntime.config.apiUrl}?symbol=${nodeRuntime.config.symbol}`;

  const req = {
    url: url,
    method: "GET" as const,
  };

  nodeRuntime.log(`📡 Node fetching from: ${url}`);

  // Send the request using the HTTP client
  const resp = httpClient.sendRequest(nodeRuntime, req).result();

  nodeRuntime.log(`✅ Response received, status: ${resp.statusCode}`);

  // Parse the response body
  const bodyText = new TextDecoder().decode(resp.body);
  const orderBook: OrderBook = JSON.parse(bodyText);

  nodeRuntime.log(`📊 Parsed order book: ${orderBook.bids.length} bids, ${orderBook.asks.length} asks`);

  return orderBook;
};

/**
 * Simple consensus: just take the first result
 * In production, you could implement more sophisticated consensus logic
 */
const simpleConsensus = () => (results: OrderBook[]): OrderBook => {
  if (!results || results.length === 0) {
    throw new Error('No results from nodes');
  }
  return results[0];
};

const onCronTrigger = (runtime: Runtime<Config>): LiquidityMetrics => {
  runtime.log('🔄 ScaleX Liquidity Calculator Starting...');

  // Use runInNodeMode to execute the offchain fetch with consensus
  // Note the pattern: runInNodeMode(fetchFn, consensusFn)().result()
  const orderBook = runtime.runInNodeMode(
    fetchOrderBook,
    simpleConsensus()
  )().result();

  if (!orderBook || !orderBook.bids || !orderBook.asks) {
    throw new Error('Invalid order book data received');
  }

  runtime.log(`✅ Order book loaded: ${orderBook.bids.length} bids, ${orderBook.asks.length} asks`);
  runtime.log(`📊 Last Update ID: ${orderBook.lastUpdateId}`);

  runtime.log('💧 Calculating liquidity metrics...');
  const metrics = calculateLiquidityMetrics(orderBook, runtime.config.symbol);

  runtime.log('============================================================');
  runtime.log(`📈 LIQUIDITY METRICS FOR ${metrics.symbol}`);
  runtime.log('============================================================');
  runtime.log(`🕐 Timestamp: ${new Date(metrics.timestamp).toISOString()}`);
  runtime.log(`💱 Mid Price: ${metrics.midPrice}`);
  runtime.log(`📊 Spread: ${toFixed(metrics.spread, 2)} (${toFixed(metrics.spreadBps, 2)} bps)`);
  runtime.log(`📊 Order Book Depth: ${metrics.bidLevels} bids, ${metrics.askLevels} asks`);
  runtime.log(`💧 Total Liquidity:`);
  runtime.log(`   Bids: ${toFixed(metrics.totalBidLiquidityETH, 6)} ETH`);
  runtime.log(`   Asks: ${toFixed(metrics.totalAskLiquidityETH, 6)} ETH`);
  runtime.log(`   Combined: ${toFixed(metrics.totalBidLiquidityETH + metrics.totalAskLiquidityETH, 6)} ETH`);
  runtime.log(`📏 Liquidity Depth:`);
  runtime.log(`   1% - Bids: ${toFixed(metrics.liquidity1PercentDepth.bids, 6)} ETH, Asks: ${toFixed(metrics.liquidity1PercentDepth.asks, 6)} ETH`);
  runtime.log(`   5% - Bids: ${toFixed(metrics.liquidity5PercentDepth.bids, 6)} ETH, Asks: ${toFixed(metrics.liquidity5PercentDepth.asks, 6)} ETH`);
  runtime.log('============================================================');

  return metrics;
};

const initWorkflow = (config: Config) => {
  const cron = new CronCapability();

  return [
    handler(
      cron.trigger({ schedule: config.schedule }),
      onCronTrigger
    ),
  ];
};

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}
