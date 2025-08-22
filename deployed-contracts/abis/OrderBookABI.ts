export const OrderBookABI: any[] = [
	{
		type: "constructor",
		inputs: [],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "placeLimitOrder",
		inputs: [
			{
				name: "poolId",
				type: "bytes32",
				internalType: "PoolId",
			},
			{
				name: "zeroForOne",
				type: "bool",
				internalType: "bool",
			},
			{
				name: "tickLower",
				type: "int24",
				internalType: "int24",
			},
			{
				name: "tickUpper",
				type: "int24",
				internalType: "int24",
			},
			{
				name: "liquidity",
				type: "uint128",
				internalType: "uint128",
			},
		],
		outputs: [
			{
				name: "orderId",
				type: "uint256",
				internalType: "uint256",
			},
		],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "cancelLimitOrder",
		inputs: [
			{
				name: "orderId",
				type: "uint256",
				internalType: "uint256",
			},
		],
		outputs: [],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "executeMarketOrder",
		inputs: [
			{
				name: "poolId",
				type: "bytes32",
				internalType: "PoolId",
			},
			{
				name: "zeroForOne",
				type: "bool",
				internalType: "bool",
			},
			{
				name: "amountSpecified",
				type: "int256",
				internalType: "int256",
			},
			{
				name: "sqrtPriceLimitX96",
				type: "uint160",
				internalType: "uint160",
			},
		],
		outputs: [
			{
				name: "amountIn",
				type: "uint256",
				internalType: "uint256",
			},
			{
				name: "amountOut",
				type: "uint256",
				internalType: "uint256",
			},
		],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "getOrder",
		inputs: [
			{
				name: "orderId",
				type: "uint256",
				internalType: "uint256",
			},
		],
		outputs: [
			{
				name: "",
				type: "tuple",
				internalType: "struct OrderBook.Order",
				components: [
					{
						name: "owner",
						type: "address",
						internalType: "address",
					},
					{
						name: "poolId",
						type: "bytes32",
						internalType: "PoolId",
					},
					{
						name: "zeroForOne",
						type: "bool",
						internalType: "bool",
					},
					{
						name: "tickLower",
						type: "int24",
						internalType: "int24",
					},
					{
						name: "tickUpper",
						type: "int24",
						internalType: "int24",
					},
					{
						name: "liquidity",
						type: "uint128",
						internalType: "uint128",
					},
					{
						name: "isActive",
						type: "bool",
						internalType: "bool",
					},
				],
			},
		],
		stateMutability: "view",
	},
	{
		type: "function",
		name: "getUserOrders",
		inputs: [
			{
				name: "user",
				type: "address",
				internalType: "address",
			},
		],
		outputs: [
			{
				name: "",
				type: "uint256[]",
				internalType: "uint256[]",
			},
		],
		stateMutability: "view",
	},
	{
		type: "event",
		name: "LimitOrderPlaced",
		inputs: [
			{
				name: "orderId",
				type: "uint256",
				indexed: true,
				internalType: "uint256",
			},
			{
				name: "owner",
				type: "address",
				indexed: true,
				internalType: "address",
			},
			{
				name: "poolId",
				type: "bytes32",
				indexed: true,
				internalType: "PoolId",
			},
			{
				name: "zeroForOne",
				type: "bool",
				indexed: false,
				internalType: "bool",
			},
			{
				name: "tickLower",
				type: "int24",
				indexed: false,
				internalType: "int24",
			},
			{
				name: "tickUpper",
				type: "int24",
				indexed: false,
				internalType: "int24",
			},
			{
				name: "liquidity",
				type: "uint128",
				indexed: false,
				internalType: "uint128",
			},
		],
		anonymous: false,
	},
	{
		type: "event",
		name: "LimitOrderCancelled",
		inputs: [
			{
				name: "orderId",
				type: "uint256",
				indexed: true,
				internalType: "uint256",
			},
			{
				name: "owner",
				type: "address",
				indexed: true,
				internalType: "address",
			},
		],
		anonymous: false,
	},
	{
		type: "event",
		name: "MarketOrderExecuted",
		inputs: [
			{
				name: "user",
				type: "address",
				indexed: true,
				internalType: "address",
			},
			{
				name: "poolId",
				type: "bytes32",
				indexed: true,
				internalType: "PoolId",
			},
			{
				name: "zeroForOne",
				type: "bool",
				indexed: false,
				internalType: "bool",
			},
			{
				name: "amountIn",
				type: "uint256",
				indexed: false,
				internalType: "uint256",
			},
			{
				name: "amountOut",
				type: "uint256",
				indexed: false,
				internalType: "uint256",
			},
		],
		anonymous: false,
	},
] as const;