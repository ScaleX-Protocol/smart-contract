/**
 * Chainlink Functions - Agent Metrics Computation
 *
 * This script computes complex metrics for AI agents that require off-chain computation:
 * - Daily/weekly trading volume
 * - Portfolio drawdown (daily/weekly)
 * - Performance metrics (win rate, Sharpe ratio, PnL)
 * - Reputation score from ERC-8004 registry
 *
 * Arguments:
 * - args[0]: owner address
 * - args[1]: agentTokenId
 * - args[2]: metricsType (0=DAILY_VOLUME, 1=DAILY_DRAWDOWN, 2=WEEKLY_VOLUME, etc.)
 * - args[3]: timestamp
 *
 * Returns:
 * - Encoded metrics based on metricsType
 */

// Configuration - Update with your indexer API endpoint
const INDEXER_API_URL = secrets.indexerApiUrl || "https://api.scalex.example.com";
const REPUTATION_REGISTRY_ADDRESS = secrets.reputationRegistry || "0x...";

// Metrics type enum
const MetricsType = {
  DAILY_VOLUME: 0,
  DAILY_DRAWDOWN: 1,
  WEEKLY_VOLUME: 2,
  WEEKLY_DRAWDOWN: 3,
  PERFORMANCE_METRICS: 4,
  FULL_CHECK: 5
};

// Parse arguments
const owner = args[0];
const agentTokenId = args[1];
const metricsType = parseInt(args[2]);
const timestamp = parseInt(args[3]);

// Calculate time windows
const ONE_DAY = 86400;
const ONE_WEEK = 604800;
const dailyStart = timestamp - ONE_DAY;
const weeklyStart = timestamp - ONE_WEEK;

/**
 * Fetch agent trading history from indexer
 */
async function fetchTradingHistory(owner, agentTokenId, startTime, endTime) {
  const url = `${INDEXER_API_URL}/agents/${owner}/${agentTokenId}/trades?start=${startTime}&end=${endTime}`;

  const response = await Functions.makeHttpRequest({
    url: url,
    method: "GET",
    headers: {
      "Content-Type": "application/json"
    }
  });

  if (response.error) {
    throw new Error(`Indexer API error: ${response.message}`);
  }

  return response.data.trades || [];
}

/**
 * Fetch agent portfolio snapshots from indexer
 */
async function fetchPortfolioSnapshots(owner, agentTokenId, startTime, endTime) {
  const url = `${INDEXER_API_URL}/agents/${owner}/${agentTokenId}/portfolio?start=${startTime}&end=${endTime}`;

  const response = await Functions.makeHttpRequest({
    url: url,
    method: "GET"
  });

  if (response.error) {
    throw new Error(`Indexer API error: ${response.message}`);
  }

  return response.data.snapshots || [];
}

/**
 * Fetch reputation score from ERC-8004 registry
 */
async function fetchReputationScore(agentTokenId) {
  // In production, this would query the blockchain via RPC
  // For now, fetch from indexer which caches reputation data
  const url = `${INDEXER_API_URL}/reputation/${agentTokenId}`;

  const response = await Functions.makeHttpRequest({
    url: url,
    method: "GET"
  });

  if (response.error) {
    return 50; // Default score if unavailable
  }

  return response.data.score || 50;
}

/**
 * Compute daily trading volume
 */
async function computeDailyVolume() {
  const trades = await fetchTradingHistory(owner, agentTokenId, dailyStart, timestamp);

  let totalVolume = 0;
  for (const trade of trades) {
    // Volume in quote currency (e.g., USDC)
    totalVolume += parseFloat(trade.volumeQuote || 0);
  }

  // Return as uint256 (in wei for 6 decimal tokens)
  return Math.floor(totalVolume * 1e6);
}

/**
 * Compute weekly trading volume
 */
async function computeWeeklyVolume() {
  const trades = await fetchTradingHistory(owner, agentTokenId, weeklyStart, timestamp);

  let totalVolume = 0;
  for (const trade of trades) {
    totalVolume += parseFloat(trade.volumeQuote || 0);
  }

  return Math.floor(totalVolume * 1e6);
}

/**
 * Compute daily portfolio drawdown in basis points
 */
async function computeDailyDrawdown() {
  const snapshots = await fetchPortfolioSnapshots(owner, agentTokenId, dailyStart, timestamp);

  if (snapshots.length === 0) {
    return 0; // No data, no drawdown
  }

  // Get start and current values
  const startValue = parseFloat(snapshots[0].totalValue || 0);
  const currentValue = parseFloat(snapshots[snapshots.length - 1].totalValue || 0);

  if (startValue === 0) {
    return 0;
  }

  // Calculate peak value during period
  let peakValue = startValue;
  for (const snapshot of snapshots) {
    const value = parseFloat(snapshot.totalValue || 0);
    if (value > peakValue) {
      peakValue = value;
    }
  }

  // Drawdown = (Peak - Current) / Peak * 10000 (basis points)
  const drawdown = ((peakValue - currentValue) / peakValue) * 10000;

  return Math.max(0, Math.floor(drawdown));
}

/**
 * Compute weekly portfolio drawdown in basis points
 */
async function computeWeeklyDrawdown() {
  const snapshots = await fetchPortfolioSnapshots(owner, agentTokenId, weeklyStart, timestamp);

  if (snapshots.length === 0) {
    return 0;
  }

  const startValue = parseFloat(snapshots[0].totalValue || 0);
  const currentValue = parseFloat(snapshots[snapshots.length - 1].totalValue || 0);

  if (startValue === 0) {
    return 0;
  }

  let peakValue = startValue;
  for (const snapshot of snapshots) {
    const value = parseFloat(snapshot.totalValue || 0);
    if (value > peakValue) {
      peakValue = value;
    }
  }

  const drawdown = ((peakValue - currentValue) / peakValue) * 10000;

  return Math.max(0, Math.floor(drawdown));
}

/**
 * Compute performance metrics (win rate, Sharpe ratio, reputation)
 */
async function computePerformanceMetrics() {
  const trades = await fetchTradingHistory(owner, agentTokenId, weeklyStart, timestamp);
  const reputationScore = await fetchReputationScore(agentTokenId);

  // Calculate win rate
  let profitableTrades = 0;
  let totalTrades = trades.length;
  let totalPnL = 0;
  let pnlSquaredSum = 0;

  for (const trade of trades) {
    const pnl = parseFloat(trade.pnl || 0);
    totalPnL += pnl;
    pnlSquaredSum += pnl * pnl;

    if (pnl > 0) {
      profitableTrades++;
    }
  }

  // Win rate in basis points (0-10000)
  const winRateBps = totalTrades > 0
    ? Math.floor((profitableTrades / totalTrades) * 10000)
    : 0;

  // Simplified Sharpe ratio (assuming 0% risk-free rate)
  // Sharpe = mean(returns) / std(returns) * sqrt(252) for annualized
  // Return as integer with 2 decimals precision (multiply by 100)
  let sharpeRatio = 0;
  if (totalTrades > 1) {
    const meanPnL = totalPnL / totalTrades;
    const variance = (pnlSquaredSum / totalTrades) - (meanPnL * meanPnL);
    const stdDev = Math.sqrt(Math.max(0, variance));

    if (stdDev > 0) {
      sharpeRatio = Math.floor((meanPnL / stdDev) * Math.sqrt(252) * 100);
    }
  }

  // Return tuple: (winRateBps, sharpeRatio, reputationScore)
  return Functions.encodeUint256(winRateBps) +
         Functions.encodeUint256(sharpeRatio).slice(2) +
         Functions.encodeUint256(reputationScore).slice(2);
}

/**
 * Compute full metrics check
 */
async function computeFullMetrics() {
  // Fetch all required data
  const [
    dailyVolume,
    weeklyVolume,
    dailyDrawdown,
    weeklyDrawdown
  ] = await Promise.all([
    computeDailyVolume(),
    computeWeeklyVolume(),
    computeDailyDrawdown(),
    computeWeeklyDrawdown()
  ]);

  const trades = await fetchTradingHistory(owner, agentTokenId, weeklyStart, timestamp);
  const reputationScore = await fetchReputationScore(agentTokenId);

  // Calculate performance metrics
  let profitableTrades = 0;
  let totalTrades = trades.length;
  let totalPnL = 0;
  let pnlSquaredSum = 0;

  for (const trade of trades) {
    const pnl = parseFloat(trade.pnl || 0);
    totalPnL += pnl;
    pnlSquaredSum += pnl * pnl;

    if (pnl > 0) {
      profitableTrades++;
    }
  }

  const winRateBps = totalTrades > 0
    ? Math.floor((profitableTrades / totalTrades) * 10000)
    : 0;

  let sharpeRatio = 0;
  if (totalTrades > 1) {
    const meanPnL = totalPnL / totalTrades;
    const variance = (pnlSquaredSum / totalTrades) - (meanPnL * meanPnL);
    const stdDev = Math.sqrt(Math.max(0, variance));

    if (stdDev > 0) {
      sharpeRatio = Math.floor((meanPnL / stdDev) * Math.sqrt(252) * 100);
    }
  }

  // Return tuple of all metrics
  // (dailyVolume, weeklyVolume, dailyDrawdownBps, weeklyDrawdownBps, winRateBps, sharpeRatio, reputationScore)
  return Functions.encodeUint256(dailyVolume) +
         Functions.encodeUint256(weeklyVolume).slice(2) +
         Functions.encodeUint256(dailyDrawdown).slice(2) +
         Functions.encodeUint256(weeklyDrawdown).slice(2) +
         Functions.encodeUint256(winRateBps).slice(2) +
         Functions.encodeUint256(sharpeRatio).slice(2) +
         Functions.encodeUint256(reputationScore).slice(2);
}

// Main execution
try {
  let result;

  switch (metricsType) {
    case MetricsType.DAILY_VOLUME:
      const dailyVol = await computeDailyVolume();
      result = Functions.encodeUint256(dailyVol);
      break;

    case MetricsType.DAILY_DRAWDOWN:
      const dailyDD = await computeDailyDrawdown();
      result = Functions.encodeUint256(dailyDD);
      break;

    case MetricsType.WEEKLY_VOLUME:
      const weeklyVol = await computeWeeklyVolume();
      result = Functions.encodeUint256(weeklyVol);
      break;

    case MetricsType.WEEKLY_DRAWDOWN:
      const weeklyDD = await computeWeeklyDrawdown();
      result = Functions.encodeUint256(weeklyDD);
      break;

    case MetricsType.PERFORMANCE_METRICS:
      result = await computePerformanceMetrics();
      break;

    case MetricsType.FULL_CHECK:
      result = await computeFullMetrics();
      break;

    default:
      throw new Error(`Unknown metrics type: ${metricsType}`);
  }

  // Return the result as bytes
  return Functions.encodeString(result);

} catch (error) {
  // Return error message
  return Functions.encodeString(`ERROR: ${error.message}`);
}
