export const BalanceManagerABI: any[] = [
	{
		type: "constructor",
		inputs: [],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "deposit",
		inputs: [
			{
				name: "currency",
				type: "address",
				internalType: "Currency",
			},
			{
				name: "amount",
				type: "uint256",
				internalType: "uint256",
			},
			{
				name: "sender",
				type: "address",
				internalType: "address",
			},
			{
				name: "user",
				type: "address",
				internalType: "address",
			},
		],
		outputs: [],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "withdraw",
		inputs: [
			{
				name: "currency",
				type: "address",
				internalType: "Currency",
			},
			{
				name: "amount",
				type: "uint256",
				internalType: "uint256",
			},
			{
				name: "user",
				type: "address",
				internalType: "address",
			},
			{
				name: "destinationChainId",
				type: "uint256",
				internalType: "uint256",
			},
		],
		outputs: [],
		stateMutability: "nonpayable",
	},
	{
		type: "function",
		name: "balanceOf",
		inputs: [
			{
				name: "user",
				type: "address",
				internalType: "address",
			},
			{
				name: "currency",
				type: "address",
				internalType: "Currency",
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
		name: "handle",
		inputs: [
			{
				name: "_origin",
				type: "uint32",
				internalType: "uint32",
			},
			{
				name: "_sender",
				type: "bytes32",
				internalType: "bytes32",
			},
			{
				name: "_message",
				type: "bytes",
				internalType: "bytes",
			},
		],
		outputs: [],
		stateMutability: "payable",
	},
	{
		type: "event",
		name: "CrossChainDepositReceived",
		inputs: [
			{
				name: "user",
				type: "address",
				indexed: true,
				internalType: "address",
			},
			{
				name: "token",
				type: "address",
				indexed: true,
				internalType: "address",
			},
			{
				name: "amount",
				type: "uint256",
				indexed: false,
				internalType: "uint256",
			},
			{
				name: "syntheticToken",
				type: "address",
				indexed: false,
				internalType: "address",
			},
		],
		anonymous: false,
	},
	{
		type: "event",
		name: "Deposit",
		inputs: [
			{
				name: "user",
				type: "address",
				indexed: true,
				internalType: "address",
			},
			{
				name: "currency",
				type: "address",
				indexed: true,
				internalType: "Currency",
			},
			{
				name: "amount",
				type: "uint256",
				indexed: false,
				internalType: "uint256",
			},
		],
		anonymous: false,
	},
] as const;
