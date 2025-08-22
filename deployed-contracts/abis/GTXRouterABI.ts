export const GTXRouterABI: any[] = [
	{
		type: "constructor",
		inputs: [],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "swapExactInputSingle",
		inputs: [
			{
				name: "params",
				type: "tuple",
				internalType: "struct IGTXRouter.ExactInputSingleParams",
				components: [
					{
						name: "tokenIn",
						type: "address",
						internalType: "address",
					},
					{
						name: "tokenOut",
						type: "address",
						internalType: "address",
					},
					{
						name: "fee",
						type: "uint24",
						internalType: "uint24",
					},
					{
						name: "recipient",
						type: "address",
						internalType: "address",
					},
					{
						name: "deadline",
						type: "uint256",
						internalType: "uint256",
					},
					{
						name: "amountIn",
						type: "uint256",
						internalType: "uint256",
					},
					{
						name: "amountOutMinimum",
						type: "uint256",
						internalType: "uint256",
					},
					{
						name: "sqrtPriceLimitX96",
						type: "uint160",
						internalType: "uint160",
					},
				],
			},
		],
		outputs: [
			{
				name: "amountOut",
				type: "uint256",
				internalType: "uint256",
			},
		],
		stateMutability: "payable",
	},
	{
		type: "function",
		name: "addLiquidity",
		inputs: [
			{
				name: "params",
				type: "tuple",
				internalType: "struct IGTXRouter.AddLiquidityParams",
				components: [
					{
						name: "currency0",
						type: "address",
						internalType: "Currency",
					},
					{
						name: "currency1",
						type: "address",
						internalType: "Currency",
					},
					{
						name: "fee",
						type: "uint24",
						internalType: "uint24",
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
						name: "amount0Desired",
						type: "uint256",
						internalType: "uint256",
					},
					{
						name: "amount1Desired",
						type: "uint256",
						internalType: "uint256",
					},
					{
						name: "amount0Min",
						type: "uint256",
						internalType: "uint256",
					},
					{
						name: "amount1Min",
						type: "uint256",
						internalType: "uint256",
					},
					{
						name: "recipient",
						type: "address",
						internalType: "address",
					},
					{
						name: "deadline",
						type: "uint256",
						internalType: "uint256",
					},
				],
			},
		],
		outputs: [
			{
				name: "liquidity",
				type: "uint128",
				internalType: "uint128",
			},
			{
				name: "amount0",
				type: "uint256",
				internalType: "uint256",
			},
			{
				name: "amount1",
				type: "uint256",
				internalType: "uint256",
			},
		],
		stateMutability: "payable",
	},
	{
		type: "function",
		name: "removeLiquidity",
		inputs: [
			{
				name: "params",
				type: "tuple",
				internalType: "struct IGTXRouter.RemoveLiquidityParams",
				components: [
					{
						name: "tokenId",
						type: "uint256",
						internalType: "uint256",
					},
					{
						name: "liquidity",
						type: "uint128",
						internalType: "uint128",
					},
					{
						name: "amount0Min",
						type: "uint256",
						internalType: "uint256",
					},
					{
						name: "amount1Min",
						type: "uint256",
						internalType: "uint256",
					},
					{
						name: "deadline",
						type: "uint256",
						internalType: "uint256",
					},
				],
			},
		],
		outputs: [
			{
				name: "amount0",
				type: "uint256",
				internalType: "uint256",
			},
			{
				name: "amount1",
				type: "uint256",
				internalType: "uint256",
			},
		],
		stateMutability: "nonpayable",
	},
	{
		type: "event",
		name: "SwapExecuted",
		inputs: [
			{
				name: "tokenIn",
				type: "address",
				indexed: true,
				internalType: "address",
			},
			{
				name: "tokenOut",
				type: "address",
				indexed: true,
				internalType: "address",
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
			{
				name: "recipient",
				type: "address",
				indexed: true,
				internalType: "address",
			},
		],
		anonymous: false,
	},
] as const;