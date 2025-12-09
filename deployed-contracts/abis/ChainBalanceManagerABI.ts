export const ChainBalanceManagerABI: any[] = [
	{
		"type": "constructor",
		"inputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "addToken",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "addWhitelistedToken",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "balanceOf",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [
			{
				"name": "",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "claim",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "amount",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "deposit",
		"inputs": [
			{
				"name": "to",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "currency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "amount",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"outputs": [
			{
				"name": "depositedAmount",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"stateMutability": "payable"
	},
	{
		"type": "function",
		"name": "deposit",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "amount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "recipient",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "payable"
	},
	{
		"type": "function",
		"name": "getBalance",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "currency",
				"type": "address",
				"internalType": "Currency"
			}
		],
		"outputs": [
			{
				"name": "",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getCrossChainConfig",
		"inputs": [],
		"outputs": [
			{
				"name": "destinationDomain",
				"type": "uint32",
				"internalType": "uint32"
			},
			{
				"name": "destinationBalanceManager",
				"type": "address",
				"internalType": "address"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getCrossChainInfo",
		"inputs": [],
		"outputs": [
			{
				"name": "mailbox",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "localDomain",
				"type": "uint32",
				"internalType": "uint32"
			},
			{
				"name": "destinationDomain",
				"type": "uint32",
				"internalType": "uint32"
			},
			{
				"name": "destinationBalanceManager",
				"type": "address",
				"internalType": "address"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getDestinationConfig",
		"inputs": [],
		"outputs": [
			{
				"name": "destinationDomain",
				"type": "uint32",
				"internalType": "uint32"
			},
			{
				"name": "destinationBalanceManager",
				"type": "address",
				"internalType": "address"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getLockedBalance",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "manager",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "currency",
				"type": "address",
				"internalType": "Currency"
			}
		],
		"outputs": [
			{
				"name": "",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getMailboxConfig",
		"inputs": [],
		"outputs": [
			{
				"name": "mailbox",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "localDomain",
				"type": "uint32",
				"internalType": "uint32"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getReverseTokenMapping",
		"inputs": [
			{
				"name": "syntheticToken",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [
			{
				"name": "",
				"type": "address",
				"internalType": "address"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getTokenCount",
		"inputs": [],
		"outputs": [
			{
				"name": "",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getTokenMapping",
		"inputs": [
			{
				"name": "sourceToken",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [
			{
				"name": "",
				"type": "address",
				"internalType": "address"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getUnlockedBalance",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [
			{
				"name": "",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getUserNonce",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [
			{
				"name": "",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getWhitelistedTokens",
		"inputs": [],
		"outputs": [
			{
				"name": "",
				"type": "address[]",
				"internalType": "address[]"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "handle",
		"inputs": [
			{
				"name": "_origin",
				"type": "uint32",
				"internalType": "uint32"
			},
			{
				"name": "_sender",
				"type": "bytes32",
				"internalType": "bytes32"
			},
			{
				"name": "_messageBody",
				"type": "bytes",
				"internalType": "bytes"
			}
		],
		"outputs": [],
		"stateMutability": "payable"
	},
	{
		"type": "function",
		"name": "initialize",
		"inputs": [
			{
				"name": "",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "initialize",
		"inputs": [
			{
				"name": "_owner",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "_mailbox",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "_destinationDomain",
				"type": "uint32",
				"internalType": "uint32"
			},
			{
				"name": "_destinationBalanceManager",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "initializeCrossChain",
		"inputs": [
			{
				"name": "_owner",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "_mailbox",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "_destinationDomain",
				"type": "uint32",
				"internalType": "uint32"
			},
			{
				"name": "_destinationBalanceManager",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "isMessageProcessed",
		"inputs": [
			{
				"name": "messageId",
				"type": "bytes32",
				"internalType": "bytes32"
			}
		],
		"outputs": [
			{
				"name": "",
				"type": "bool",
				"internalType": "bool"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "isTokenWhitelisted",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [
			{
				"name": "",
				"type": "bool",
				"internalType": "bool"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "lock",
		"inputs": [
			{
				"name": "to",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "currency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "amount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "owner",
		"inputs": [],
		"outputs": [
			{
				"name": "",
				"type": "address",
				"internalType": "address"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "removeToken",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "renounceOwnership",
		"inputs": [],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "setTokenMapping",
		"inputs": [
			{
				"name": "sourceToken",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "syntheticToken",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "tokenList",
		"inputs": [
			{
				"name": "index",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"outputs": [
			{
				"name": "",
				"type": "address",
				"internalType": "address"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "transferOwnership",
		"inputs": [
			{
				"name": "newOwner",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "unlock",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "amount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "unlock",
		"inputs": [
			{
				"name": "to",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "currency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "amount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "manager",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "unlockedBalanceOf",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [
			{
				"name": "",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "updateCrossChainConfig",
		"inputs": [
			{
				"name": "_destinationDomain",
				"type": "uint32",
				"internalType": "uint32"
			},
			{
				"name": "_destinationBalanceManager",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "updateCrossChainConfig",
		"inputs": [
			{
				"name": "_mailbox",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "_destinationDomain",
				"type": "uint32",
				"internalType": "uint32"
			},
			{
				"name": "_destinationBalanceManager",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "updateLocalDomain",
		"inputs": [
			{
				"name": "_localDomain",
				"type": "uint32",
				"internalType": "uint32"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "whitelistedTokens",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [
			{
				"name": "",
				"type": "bool",
				"internalType": "bool"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "withdraw",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "amount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "withdraw",
		"inputs": [
			{
				"name": "to",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "currency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "amount",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "event",
		"name": "BridgeToSynthetic",
		"inputs": [
			{
				"name": "to",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "sourceToken",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "syntheticToken",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "amount",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "Claim",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "token",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "amount",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "CrossChainConfigUpdated",
		"inputs": [
			{
				"name": "destinationDomain",
				"type": "uint32",
				"indexed": true,
				"internalType": "uint32"
			},
			{
				"name": "destinationBalanceManager",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "Deposit",
		"inputs": [
			{
				"name": "from",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "to",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "token",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "amount",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "DestinationChainConfigUpdated",
		"inputs": [
			{
				"name": "isMailbox",
				"type": "bool",
				"indexed": false,
				"internalType": "bool"
			},
			{
				"name": "value",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "Initialized",
		"inputs": [
			{
				"name": "version",
				"type": "uint64",
				"indexed": false,
				"internalType": "uint64"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "LocalDomainUpdated",
		"inputs": [
			{
				"name": "oldDomain",
				"type": "uint32",
				"indexed": false,
				"internalType": "uint32"
			},
			{
				"name": "newDomain",
				"type": "uint32",
				"indexed": false,
				"internalType": "uint32"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "NonceIncremented",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "nonce",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "OwnershipTransferred",
		"inputs": [
			{
				"name": "previousOwner",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "newOwner",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "TokenDeposited",
		"inputs": [
			{
				"name": "to",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "token",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "amount",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "TokenMappingSet",
		"inputs": [
			{
				"name": "sourceToken",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "syntheticToken",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "TokenRemoved",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "TokenWhitelisted",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "TokenWithdrawn",
		"inputs": [
			{
				"name": "to",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "token",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "amount",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "Unlock",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "token",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "amount",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "Withdraw",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "token",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "amount",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "WithdrawMessageReceived",
		"inputs": [
			{
				"name": "recipient",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "sourceToken",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "amount",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "error",
		"name": "DifferentChainDomains",
		"inputs": [
			{
				"name": "local",
				"type": "uint32",
				"internalType": "uint32"
			},
			{
				"name": "destination",
				"type": "uint32",
				"internalType": "uint32"
			}
		]
	},
	{
		"type": "error",
		"name": "EthSentForErc20Deposit",
		"inputs": []
	},
	{
		"type": "error",
		"name": "InsufficientBalance",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "tokenId",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "requested",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "available",
				"type": "uint256",
				"internalType": "uint256"
			}
		]
	},
	{
		"type": "error",
		"name": "InsufficientLockedBalance",
		"inputs": []
	},
	{
		"type": "error",
		"name": "InsufficientUnlockedBalance",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "tokenId",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "requested",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "available",
				"type": "uint256",
				"internalType": "uint256"
			}
		]
	},
	{
		"type": "error",
		"name": "InvalidAmount",
		"inputs": []
	},
	{
		"type": "error",
		"name": "InvalidInitialization",
		"inputs": []
	},
	{
		"type": "error",
		"name": "InvalidMessageType",
		"inputs": [
			{
				"name": "messageType",
				"type": "uint256",
				"internalType": "uint256"
			}
		]
	},
	{
		"type": "error",
		"name": "InvalidOrigin",
		"inputs": [
			{
				"name": "origin",
				"type": "uint32",
				"internalType": "uint32"
			}
		]
	},
	{
		"type": "error",
		"name": "InvalidSender",
		"inputs": [
			{
				"name": "sender",
				"type": "bytes32",
				"internalType": "bytes32"
			}
		]
	},
	{
		"type": "error",
		"name": "InvalidSyntheticToken",
		"inputs": [
			{
				"name": "syntheticToken",
				"type": "address",
				"internalType": "address"
			}
		]
	},
	{
		"type": "error",
		"name": "MessageAlreadyProcessed",
		"inputs": [
			{
				"name": "messageId",
				"type": "bytes32",
				"internalType": "bytes32"
			}
		]
	},
	{
		"type": "error",
		"name": "NotInitializing",
		"inputs": []
	},
	{
		"type": "error",
		"name": "OnlyMailbox",
		"inputs": []
	},
	{
		"type": "error",
		"name": "OwnableInvalidOwner",
		"inputs": [
			{
				"name": "owner",
				"type": "address",
				"internalType": "address"
			}
		]
	},
	{
		"type": "error",
		"name": "OwnableUnauthorizedAccount",
		"inputs": [
			{
				"name": "account",
				"type": "address",
				"internalType": "address"
			}
		]
	},
	{
		"type": "error",
		"name": "ReentrancyGuardReentrantCall",
		"inputs": []
	},
	{
		"type": "error",
		"name": "SafeERC20FailedOperation",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			}
		]
	},
	{
		"type": "error",
		"name": "TokenAlreadyWhitelisted",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			}
		]
	},
	{
		"type": "error",
		"name": "TokenMappingNotFound",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			}
		]
	},
	{
		"type": "error",
		"name": "TokenNotFound",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			}
		]
	},
	{
		"type": "error",
		"name": "TokenNotWhitelisted",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"internalType": "address"
			}
		]
	},
	{
		"type": "error",
		"name": "ZeroAddress",
		"inputs": []
	},
	{
		"type": "error",
		"name": "ZeroAmount",
		"inputs": []
	}
] as const;