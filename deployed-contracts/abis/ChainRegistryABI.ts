export const ChainRegistryABI: any[] = [
	{
		type: "constructor",
		inputs: [],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "getActiveChains",
		inputs: [],
		outputs: [
			{
				name: "",
				type: "uint32[]",
				internalType: "uint32[]",
			},
		],
		stateMutability: "view",
	},
	{
		type: "function",
		name: "getChainBalanceManager",
		inputs: [
			{
				name: "chainId",
				type: "uint32",
				internalType: "uint32",
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
		name: "getChainInfo",
		inputs: [
			{
				name: "chainId",
				type: "uint32",
				internalType: "uint32",
			},
		],
		outputs: [
			{
				name: "name",
				type: "string",
				internalType: "string",
			},
			{
				name: "chainBalanceManager",
				type: "address",
				internalType: "address",
			},
			{
				name: "isActive",
				type: "bool",
				internalType: "bool",
			},
		],
		stateMutability: "view",
	},
	{
		type: "function",
		name: "isChainRegistered",
		inputs: [
			{
				name: "chainId",
				type: "uint32",
				internalType: "uint32",
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
		name: "registerChain",
		inputs: [
			{
				name: "chainId",
				type: "uint32",
				internalType: "uint32",
			},
			{
				name: "name",
				type: "string",
				internalType: "string",
			},
			{
				name: "chainBalanceManager",
				type: "address",
				internalType: "address",
			},
		],
		outputs: [],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "updateChainStatus",
		inputs: [
			{
				name: "chainId",
				type: "uint32",
				internalType: "uint32",
			},
			{
				name: "isActive",
				type: "bool",
				internalType: "bool",
			},
		],
		outputs: [],
		stateMutability: "nonpayable",
	},
	{
		type: "event",
		name: "ChainRegistered",
		inputs: [
			{
				name: "chainId",
				type: "uint32",
				indexed: true,
				internalType: "uint32",
			},
			{
				name: "name",
				type: "string",
				indexed: false,
				internalType: "string",
			},
			{
				name: "chainBalanceManager",
				type: "address",
				indexed: true,
				internalType: "address",
			},
		],
		anonymous: false,
	},
	{
		type: "event",
		name: "ChainStatusUpdated",
		inputs: [
			{
				name: "chainId",
				type: "uint32",
				indexed: true,
				internalType: "uint32",
			},
			{
				name: "isActive",
				type: "bool",
				indexed: false,
				internalType: "bool",
			},
		],
		anonymous: false,
	},
] as const;