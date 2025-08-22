export const SyntheticTokenFactoryABI: any[] = [
	{
		type: "constructor",
		inputs: [],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "batchCreateSyntheticTokens",
		inputs: [
			{
				name: "names",
				type: "string[]",
				internalType: "string[]",
			},
			{
				name: "symbols",
				type: "string[]",
				internalType: "string[]",
			},
			{
				name: "decimals",
				type: "uint8[]",
				internalType: "uint8[]",
			},
			{
				name: "minters",
				type: "address[]",
				internalType: "address[]",
			},
		],
		outputs: [
			{
				name: "tokens",
				type: "address[]",
				internalType: "address[]",
			},
		],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "createSyntheticToken",
		inputs: [
			{
				name: "name",
				type: "string",
				internalType: "string",
			},
			{
				name: "symbol",
				type: "string",
				internalType: "string",
			},
			{
				name: "decimals",
				type: "uint8",
				internalType: "uint8",
			},
			{
				name: "minter",
				type: "address",
				internalType: "address",
			},
		],
		outputs: [
			{
				name: "",
				type: "address",
				internalType: "address",
			},
		],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "getCreatedTokens",
		inputs: [],
		outputs: [
			{
				name: "",
				type: "address[]",
				internalType: "address[]",
			},
		],
		stateMutability: "view",
	},
	{
		type: "function",
		name: "getTokenCount",
		inputs: [],
		outputs: [
			{
				name: "",
				type: "uint256",
				internalType: "uint256",
			},
		],
		stateMutability: "view",
	},
	{
		type: "function",
		name: "isTokenCreatedByFactory",
		inputs: [
			{
				name: "token",
				type: "address",
				internalType: "address",
			},
		],
		outputs: [
			{
				name: "",
				type: "bool",
				internalType: "bool",
			},
		],
		stateMutability: "view",
	},
	{
		type: "event",
		name: "SyntheticTokenCreated",
		inputs: [
			{
				name: "token",
				type: "address",
				indexed: true,
				internalType: "address",
			},
			{
				name: "name",
				type: "string",
				indexed: false,
				internalType: "string",
			},
			{
				name: "symbol",
				type: "string",
				indexed: false,
				internalType: "string",
			},
			{
				name: "decimals",
				type: "uint8",
				indexed: false,
				internalType: "uint8",
			},
			{
				name: "minter",
				type: "address",
				indexed: true,
				internalType: "address",
			},
		],
		anonymous: false,
	},
] as const;