export const TokenRegistryABI: any[] = [
	{
		type: "constructor",
		inputs: [],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "convertAmount",
		inputs: [
			{
				name: "amount",
				type: "uint256",
				internalType: "uint256",
			},
			{
				name: "fromDecimals",
				type: "uint8",
				internalType: "uint8",
			},
			{
				name: "toDecimals",
				type: "uint8",
				internalType: "uint8",
			},
		],
		outputs: [
			{
				name: "",
				type: "uint256",
				internalType: "uint256",
			},
		],
		stateMutability: "pure",
	},
	{
		type: "function",
		name: "getCurrencyId",
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
				type: "uint256",
				internalType: "uint256",
			},
		],
		stateMutability: "view",
	},
	{
		type: "function",
		name: "getRegisteredToken",
		inputs: [
			{
				name: "currencyId",
				type: "uint256",
				internalType: "uint256",
			},
		],
		outputs: [
			{
				name: "",
				type: "address",
				internalType: "address",
			},
		],
		stateMutability: "view",
	},
	{
		type: "function",
		name: "getTokenDecimals",
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
				type: "uint8",
				internalType: "uint8",
			},
		],
		stateMutability: "view",
	},
	{
		type: "function",
		name: "isRegistered",
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
		type: "function",
		name: "registerToken",
		inputs: [
			{
				name: "token",
				type: "address",
				internalType: "address",
			},
		],
		outputs: [
			{
				name: "currencyId",
				type: "uint256",
				internalType: "uint256",
			},
		],
		stateMutability: "nonpayable",
	},
	{
		type: "event",
		name: "TokenRegistered",
		inputs: [
			{
				name: "token",
				type: "address",
				indexed: true,
				internalType: "address",
			},
			{
				name: "currencyId",
				type: "uint256",
				indexed: true,
				internalType: "uint256",
			},
			{
				name: "decimals",
				type: "uint8",
				indexed: false,
				internalType: "uint8",
			},
		],
		anonymous: false,
	},
] as const;