export const PoolManagerABI: any[] = [
	{
		type: "constructor",
		inputs: [],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "createPool",
		inputs: [
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
				name: "tickSpacing",
				type: "int24",
				internalType: "int24",
			},
			{
				name: "sqrtPriceX96",
				type: "uint160",
				internalType: "uint160",
			},
		],
		outputs: [
			{
				name: "poolId",
				type: "bytes32",
				internalType: "PoolId",
			},
		],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "getPool",
		inputs: [
			{
				name: "id",
				type: "bytes32",
				internalType: "PoolId",
			},
		],
		outputs: [
			{
				name: "",
				type: "tuple",
				internalType: "struct Pool.State",
				components: [
					{
						name: "slot0",
						type: "tuple",
						internalType: "struct Pool.Slot0",
						components: [
							{
								name: "sqrtPriceX96",
								type: "uint160",
								internalType: "uint160",
							},
							{
								name: "tick",
								type: "int24",
								internalType: "int24",
							},
							{
								name: "protocolFee",
								type: "uint24",
								internalType: "uint24",
							},
							{
								name: "lpFee",
								type: "uint24",
								internalType: "uint24",
							},
						],
					},
					{
						name: "feeGrowthGlobal0X128",
						type: "uint256",
						internalType: "uint256",
					},
					{
						name: "feeGrowthGlobal1X128",
						type: "uint256",
						internalType: "uint256",
					},
					{
						name: "liquidity",
						type: "uint128",
						internalType: "uint128",
					},
				],
			},
		],
		stateMutability: "view",
	},
	{
		type: "function",
		name: "initialize",
		inputs: [
			{
				name: "_balanceManager",
				type: "address",
				internalType: "address",
			},
		],
		outputs: [],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "modifyLiquidity",
		inputs: [
			{
				name: "key",
				type: "tuple",
				internalType: "struct PoolKey",
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
						name: "tickSpacing",
						type: "int24",
						internalType: "int24",
					},
					{
						name: "hooks",
						type: "address",
						internalType: "contract IHooks",
					},
				],
			},
			{
				name: "params",
				type: "tuple",
				internalType: "struct IPoolManager.ModifyLiquidityParams",
				components: [
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
						name: "liquidityDelta",
						type: "int256",
						internalType: "int256",
					},
					{
						name: "salt",
						type: "bytes32",
						internalType: "bytes32",
					},
				],
			},
			{
				name: "hookData",
				type: "bytes",
				internalType: "bytes",
			},
		],
		outputs: [
			{
				name: "callerDelta",
				type: "tuple",
				internalType: "struct BalanceDelta",
				components: [
					{
						name: "amount0",
						type: "int128",
						internalType: "int128",
					},
					{
						name: "amount1",
						type: "int128",
						internalType: "int128",
					},
				],
			},
			{
				name: "feeDelta",
				type: "tuple",
				internalType: "struct BalanceDelta",
				components: [
					{
						name: "amount0",
						type: "int128",
						internalType: "int128",
					},
					{
						name: "amount1",
						type: "int128",
						internalType: "int128",
					},
				],
			},
		],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "swap",
		inputs: [
			{
				name: "key",
				type: "tuple",
				internalType: "struct PoolKey",
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
						name: "tickSpacing",
						type: "int24",
						internalType: "int24",
					},
					{
						name: "hooks",
						type: "address",
						internalType: "contract IHooks",
					},
				],
			},
			{
				name: "params",
				type: "tuple",
				internalType: "struct IPoolManager.SwapParams",
				components: [
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
			},
			{
				name: "hookData",
				type: "bytes",
				internalType: "bytes",
			},
		],
		outputs: [
			{
				name: "swapDelta",
				type: "tuple",
				internalType: "struct BalanceDelta",
				components: [
					{
						name: "amount0",
						type: "int128",
						internalType: "int128",
					},
					{
						name: "amount1",
						type: "int128",
						internalType: "int128",
					},
				],
			},
		],
		stateMutability: "nonpayable",
	},
	{
		type: "event",
		name: "Initialize",
		inputs: [
			{
				name: "id",
				type: "bytes32",
				indexed: true,
				internalType: "PoolId",
			},
			{
				name: "currency0",
				type: "address",
				indexed: true,
				internalType: "Currency",
			},
			{
				name: "currency1",
				type: "address",
				indexed: true,
				internalType: "Currency",
			},
			{
				name: "fee",
				type: "uint24",
				indexed: false,
				internalType: "uint24",
			},
			{
				name: "tickSpacing",
				type: "int24",
				indexed: false,
				internalType: "int24",
			},
			{
				name: "hooks",
				type: "address",
				indexed: false,
				internalType: "contract IHooks",
			},
			{
				name: "sqrtPriceX96",
				type: "uint160",
				indexed: false,
				internalType: "uint160",
			},
			{
				name: "tick",
				type: "int24",
				indexed: false,
				internalType: "int24",
			},
		],
		anonymous: false,
	},
	{
		type: "event",
		name: "ModifyLiquidity",
		inputs: [
			{
				name: "id",
				type: "bytes32",
				indexed: true,
				internalType: "PoolId",
			},
			{
				name: "sender",
				type: "address",
				indexed: true,
				internalType: "address",
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
				name: "liquidityDelta",
				type: "int256",
				indexed: false,
				internalType: "int256",
			},
			{
				name: "salt",
				type: "bytes32",
				indexed: false,
				internalType: "bytes32",
			},
		],
		anonymous: false,
	},
	{
		type: "event",
		name: "Swap",
		inputs: [
			{
				name: "id",
				type: "bytes32",
				indexed: true,
				internalType: "PoolId",
			},
			{
				name: "sender",
				type: "address",
				indexed: true,
				internalType: "address",
			},
			{
				name: "amount0",
				type: "int128",
				indexed: false,
				internalType: "int128",
			},
			{
				name: "amount1",
				type: "int128",
				indexed: false,
				internalType: "int128",
			},
			{
				name: "sqrtPriceX96",
				type: "uint160",
				indexed: false,
				internalType: "uint160",
			},
			{
				name: "liquidity",
				type: "uint128",
				indexed: false,
				internalType: "uint128",
			},
			{
				name: "tick",
				type: "int24",
				indexed: false,
				internalType: "int24",
			},
			{
				name: "fee",
				type: "uint24",
				indexed: false,
				internalType: "uint24",
			},
		],
		anonymous: false,
	},
] as const;