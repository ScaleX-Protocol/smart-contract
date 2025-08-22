export const BeaconProxyABI: any[] = [
	{
		type: "constructor",
		inputs: [
			{
				name: "beacon",
				type: "address",
				internalType: "address",
			},
			{
				name: "data",
				type: "bytes",
				internalType: "bytes",
			},
		],
		stateMutability: "payable",
	},
	{
		type: "fallback",
		stateMutability: "payable",
	},
	{
		type: "receive",
		stateMutability: "payable",
	},
	{
		type: "event",
		name: "BeaconUpgraded",
		inputs: [
			{
				name: "beacon",
				type: "address",
				indexed: true,
				internalType: "address",
			},
		],
		anonymous: false,
	},
	{
		type: "error",
		name: "ERC1967InvalidBeacon",
		inputs: [
			{
				name: "beacon",
				type: "address",
				internalType: "address",
			},
		],
	},
	{
		type: "error",
		name: "ERC1967InvalidImplementation",
		inputs: [
			{
				name: "implementation",
				type: "address",
				internalType: "address",
			},
		],
	},
	{
		type: "error",
		name: "ERC1967NonPayable",
		inputs: [],
	},
] as const;