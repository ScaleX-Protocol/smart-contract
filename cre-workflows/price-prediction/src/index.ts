/**
 * Chainlink CRE Workflow: PricePrediction Settlement
 *
 * Trigger: EVM Log — SettlementRequested(uint64 marketId, address baseToken, uint256 strikePrice, uint256 openingTwap)
 * Action:  Read Oracle.getTWAP(baseToken, 300), compute outcome, submit via settleMarket()
 *
 * This workflow:
 * 1. Decodes the SettlementRequested event
 * 2. Reads Oracle TWAP for the given base token at settlement time
 * 3. Determines the binary outcome (UP/DOWN or Above/Below strike)
 * 4. Generates a signed report and submits to PricePrediction.onReport()
 *
 * Report payload encoding: abi.encode(uint64 marketId, bool outcome)
 */

import { evmLogTrigger, evmClient } from "@chainlink/cre";

// =============================================================
//                       CONFIGURATION
// =============================================================

const PREDICTION_CONTRACT = process.env.PRICE_PREDICTION_ADDRESS!;
const ORACLE_CONTRACT = process.env.ORACLE_ADDRESS!;
const TWAP_WINDOW_SECONDS = 300; // 5-minute TWAP window

// Event signature for SettlementRequested
const SETTLEMENT_REQUESTED_SIG =
  "SettlementRequested(uint64,address,uint256,uint256)";

// ABI fragments
const ORACLE_ABI = [
  {
    name: "getTWAP",
    type: "function",
    inputs: [
      { name: "token", type: "address" },
      { name: "window", type: "uint256" },
    ],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    name: "hasSufficientHistory",
    type: "function",
    inputs: [
      { name: "token", type: "address" },
      { name: "window", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
] as const;

const PREDICTION_ABI = [
  {
    name: "onReport",
    type: "function",
    inputs: [
      { name: "metadata", type: "bytes" },
      { name: "report", type: "bytes" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    name: "getMarket",
    type: "function",
    inputs: [{ name: "marketId", type: "uint64" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "id", type: "uint64" },
          { name: "marketType", type: "uint8" },
          { name: "status", type: "uint8" },
          { name: "baseToken", type: "address" },
          { name: "strikePrice", type: "uint256" },
          { name: "openingTwap", type: "uint256" },
          { name: "startTime", type: "uint256" },
          { name: "endTime", type: "uint256" },
          { name: "totalUp", type: "uint256" },
          { name: "totalDown", type: "uint256" },
          { name: "outcome", type: "bool" },
        ],
      },
    ],
    stateMutability: "view",
  },
] as const;

// Market status enum (must match PricePrediction.sol)
const MarketStatus = {
  Open: 0,
  SettlementRequested: 1,
  Settled: 2,
  Cancelled: 3,
} as const;

// Market type enum (must match PricePrediction.sol)
const MarketType = {
  Directional: 0, // UP/DOWN relative to openingTwap
  Absolute: 1,    // Above/Below strikePrice
} as const;

// =============================================================
//                       WORKFLOW
// =============================================================

export default evmLogTrigger(
  {
    contractAddress: PREDICTION_CONTRACT,
    eventSignature: SETTLEMENT_REQUESTED_SIG,
  },
  async (runtime, event) => {
    console.log("SettlementRequested event received:", event);

    // Decode event args
    const marketId = event.args.marketId as bigint;
    const baseToken = event.args.baseToken as string;
    const strikePrice = event.args.strikePrice as bigint;
    const openingTwap = event.args.openingTwap as bigint;

    console.log(`Processing settlement for market ${marketId}`);
    console.log(`  baseToken: ${baseToken}`);
    console.log(`  strikePrice: ${strikePrice}`);
    console.log(`  openingTwap: ${openingTwap}`);

    // Verify market is still pending settlement (idempotency guard)
    const market = await evmClient.read({
      contractAddress: PREDICTION_CONTRACT,
      abi: PREDICTION_ABI,
      functionName: "getMarket",
      args: [marketId],
    });

    if (market.status !== MarketStatus.SettlementRequested) {
      console.log(
        `Market ${marketId} is not pending settlement (status: ${market.status}). Skipping.`
      );
      return;
    }

    // Check oracle has sufficient history for TWAP calculation
    const hasSufficientHistory = await evmClient.read({
      contractAddress: ORACLE_CONTRACT,
      abi: ORACLE_ABI,
      functionName: "hasSufficientHistory",
      args: [baseToken as `0x${string}`, BigInt(TWAP_WINDOW_SECONDS)],
    });

    if (!hasSufficientHistory) {
      console.warn(
        `Oracle has insufficient history for ${baseToken}. Cannot settle market ${marketId}.`
      );
      // Do not revert — the market can be re-requested after more history accumulates
      return;
    }

    // Read current TWAP from Oracle at settlement time
    const currentTwap = await evmClient.read({
      contractAddress: ORACLE_CONTRACT,
      abi: ORACLE_ABI,
      functionName: "getTWAP",
      args: [baseToken as `0x${string}`, BigInt(TWAP_WINDOW_SECONDS)],
    });

    if (currentTwap === 0n) {
      console.warn(`Oracle returned 0 TWAP for ${baseToken}. Skipping.`);
      return;
    }

    console.log(`Current TWAP at settlement: ${currentTwap}`);

    // Determine outcome based on market type
    let outcome: boolean;

    if (market.marketType === MarketType.Directional) {
      // UP wins if current TWAP > openingTwap
      outcome = currentTwap > openingTwap;
      console.log(
        `Directional market: currentTwap(${currentTwap}) > openingTwap(${openingTwap}) = ${outcome} (UP wins: ${outcome})`
      );
    } else {
      // Absolute: Above wins if current TWAP >= strikePrice
      outcome = currentTwap >= strikePrice;
      console.log(
        `Absolute market: currentTwap(${currentTwap}) >= strikePrice(${strikePrice}) = ${outcome} (Above wins: ${outcome})`
      );
    }

    // Encode report payload: abi.encode(uint64 marketId, bool outcome)
    const report = encodeAbiParameters(
      [{ type: "uint64" }, { type: "bool" }],
      [marketId, outcome]
    );

    console.log(`Submitting settlement for market ${marketId}: outcome=${outcome}`);

    // Submit report via Chainlink CRE (KeystoneForwarder verifies BFT quorum,
    // then calls PricePrediction.onReport(metadata, report))
    await runtime.report({
      contractAddress: PREDICTION_CONTRACT,
      report,
    });

    console.log(`Settlement submitted for market ${marketId}. Outcome: ${outcome ? "UP/Above" : "DOWN/Below"}`);
  }
);

// =============================================================
//                    ABI ENCODING HELPER
// =============================================================

/**
 * Minimal ABI parameter encoder for (uint64, bool).
 * In production, use viem's encodeAbiParameters or ethers.js AbiCoder.
 */
function encodeAbiParameters(
  types: Array<{ type: string }>,
  values: Array<bigint | boolean>
): `0x${string}` {
  // uint64: padded to 32 bytes
  // bool: padded to 32 bytes
  const parts: string[] = [];
  for (let i = 0; i < types.length; i++) {
    const type = types[i].type;
    const value = values[i];
    if (type === "uint64" || type.startsWith("uint")) {
      parts.push(BigInt(value as bigint).toString(16).padStart(64, "0"));
    } else if (type === "bool") {
      parts.push((value ? 1n : 0n).toString(16).padStart(64, "0"));
    } else {
      throw new Error(`Unsupported type: ${type}`);
    }
  }
  return `0x${parts.join("")}` as `0x${string}`;
}
