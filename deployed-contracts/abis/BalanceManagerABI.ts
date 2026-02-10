export const BalanceManagerABI: any[] = [
	{
		"type": "constructor",
		"inputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "accrueYield",
		"inputs": [],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "addAuthorizedOperator",
		"inputs": [
			{
				"name": "operator",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "addSupportedAsset",
		"inputs": [
			{
				"name": "realToken",
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
		"name": "borrowForUser",
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
		"name": "calculateUserYield",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "syntheticToken",
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
		"name": "deposit",
		"inputs": [
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
				"name": "sender",
				"type": "address",
				"internalType": "address"
			},
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
		"stateMutability": "payable"
	},
	{
		"type": "function",
		"name": "depositAndLock",
		"inputs": [
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
				"name": "user",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "orderBook",
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
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "depositLocal",
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
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "feeMaker",
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
		"name": "feeReceiver",
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
		"name": "feeTaker",
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
		"name": "getAvailableBalance",
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
		"name": "getChainBalanceManager",
		"inputs": [
			{
				"name": "chainId",
				"type": "uint32",
				"internalType": "uint32"
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
		"name": "getCrossChainConfig",
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
		"name": "getFeeUnit",
		"inputs": [],
		"outputs": [
			{
				"name": "",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"stateMutability": "pure"
	},
	{
		"type": "function",
		"name": "getLendingManager",
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
		"name": "getLockedBalance",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "operator",
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
		"name": "getSupportedAssets",
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
		"name": "getSyntheticToken",
		"inputs": [
			{
				"name": "realToken",
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
		"name": "getTokenRegistry",
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
				"name": "_owner",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "_feeReceiver",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "_feeMaker",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "_feeTaker",
				"type": "uint256",
				"internalType": "uint256"
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
				"name": "_mailbox",
				"type": "address",
				"internalType": "address"
			},
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
		"name": "isAssetSupported",
		"inputs": [
			{
				"name": "realToken",
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
		"name": "isAuthorizedOperator",
		"inputs": [
			{
				"name": "operator",
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
		"name": "lendingManager",
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
		"name": "lock",
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
		"name": "lock",
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
			},
			{
				"name": "amount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "orderBook",
				"type": "address",
				"internalType": "address"
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
		"name": "removeSupportedAsset",
		"inputs": [
			{
				"name": "realToken",
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
		"name": "repayForUser",
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
		"name": "repayFromSyntheticBalance",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "syntheticToken",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "underlyingToken",
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
		"name": "requestWithdraw",
		"inputs": [
			{
				"name": "syntheticCurrency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "amount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "targetChainId",
				"type": "uint32",
				"internalType": "uint32"
			},
			{
				"name": "recipient",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "seizeCollateral",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "underlyingToken",
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
		"name": "setAuthorizedOperator",
		"inputs": [
			{
				"name": "operator",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "approved",
				"type": "bool",
				"internalType": "bool"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "setChainBalanceManager",
		"inputs": [
			{
				"name": "chainId",
				"type": "uint32",
				"internalType": "uint32"
			},
			{
				"name": "chainBalanceManager",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "setFees",
		"inputs": [
			{
				"name": "_feeMaker",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "_feeTaker",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "setLendingManager",
		"inputs": [
			{
				"name": "_lendingManager",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "setMailbox",
		"inputs": [
			{
				"name": "_mailbox",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "setPoolManager",
		"inputs": [
			{
				"name": "_poolManager",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "setTokenFactory",
		"inputs": [
			{
				"name": "_tokenFactory",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "setTokenRegistry",
		"inputs": [
			{
				"name": "_tokenRegistry",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "tokenFactory",
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
		"name": "transferFrom",
		"inputs": [
			{
				"name": "sender",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "receiver",
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
		"type": "function",
		"name": "transferLockedFrom",
		"inputs": [
			{
				"name": "sender",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "receiver",
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
		"type": "function",
		"name": "transferOut",
		"inputs": [
			{
				"name": "sender",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "receiver",
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
				"name": "user",
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
		"type": "function",
		"name": "updateCrossChainConfig",
		"inputs": [
			{
				"name": "_mailbox",
				"type": "address",
				"internalType": "address"
			},
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
		"name": "withdraw",
		"inputs": [
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
				"name": "user",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [
			{
				"name": "totalAmount",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "withdraw",
		"inputs": [
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
		"name": "AssetAdded",
		"inputs": [
			{
				"name": "realToken",
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
		"name": "AssetConfigured",
		"inputs": [
			{
				"name": "token",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "collateralFactor",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			},
			{
				"name": "liquidationThreshold",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			},
			{
				"name": "liquidationBonus",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			},
			{
				"name": "reserveFactor",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "AssetRemoved",
		"inputs": [
			{
				"name": "realToken",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "AutoRepayFromBalance",
		"inputs": [
			{
				"name": "user",
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
				"name": "underlyingToken",
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
		"name": "ChainBalanceManagerSet",
		"inputs": [
			{
				"name": "chainId",
				"type": "uint32",
				"indexed": true,
				"internalType": "uint32"
			},
			{
				"name": "chainBalanceManager",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "CollateralSeized",
		"inputs": [
			{
				"name": "user",
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
				"name": "underlyingToken",
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
				"name": "oldMailbox",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "newMailbox",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
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
		"name": "CrossChainDepositReceived",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "currency",
				"type": "address",
				"indexed": true,
				"internalType": "Currency"
			},
			{
				"name": "amount",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			},
			{
				"name": "sourceChain",
				"type": "uint32",
				"indexed": false,
				"internalType": "uint32"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "CrossChainInitialized",
		"inputs": [
			{
				"name": "mailbox",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "localDomain",
				"type": "uint32",
				"indexed": true,
				"internalType": "uint32"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "CrossChainWithdrawSent",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "currency",
				"type": "address",
				"indexed": true,
				"internalType": "Currency"
			},
			{
				"name": "amount",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			},
			{
				"name": "targetChain",
				"type": "uint32",
				"indexed": false,
				"internalType": "uint32"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "Deposit",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "id",
				"type": "uint256",
				"indexed": true,
				"internalType": "uint256"
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
		"name": "DepositedWithYield",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "realToken",
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
			},
			{
				"name": "timestamp",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "FeeUpdated",
		"inputs": [
			{
				"name": "feeMaker",
				"type": "uint256",
				"indexed": true,
				"internalType": "uint256"
			},
			{
				"name": "feeTaker",
				"type": "uint256",
				"indexed": true,
				"internalType": "uint256"
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
		"name": "LendingManagerSet",
		"inputs": [
			{
				"name": "lendingManager",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "LocalDeposit",
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
				"name": "syntheticToken",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "sourceAmount",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			},
			{
				"name": "syntheticAmount",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "Lock",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "id",
				"type": "uint256",
				"indexed": true,
				"internalType": "uint256"
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
		"name": "OperatorSet",
		"inputs": [
			{
				"name": "operator",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "authorized",
				"type": "bool",
				"indexed": false,
				"internalType": "bool"
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
		"name": "PoolManagerSet",
		"inputs": [
			{
				"name": "poolManager",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "TokenFactorySet",
		"inputs": [
			{
				"name": "tokenFactory",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "TransferFrom",
		"inputs": [
			{
				"name": "operator",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
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
				"name": "currencyId",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			},
			{
				"name": "amount",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			},
			{
				"name": "fee",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "TransferLockedFrom",
		"inputs": [
			{
				"name": "operator",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
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
				"name": "currencyId",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			},
			{
				"name": "amount",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			},
			{
				"name": "fee",
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
				"name": "id",
				"type": "uint256",
				"indexed": true,
				"internalType": "uint256"
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
		"name": "Withdrawal",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "id",
				"type": "uint256",
				"indexed": true,
				"internalType": "uint256"
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
		"name": "WithdrawalWithYield",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "currencyId",
				"type": "uint256",
				"indexed": true,
				"internalType": "uint256"
			},
			{
				"name": "principal",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			},
			{
				"name": "yield",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			},
			{
				"name": "remainingBalance",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "WithdrawnWithYield",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "realToken",
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
			},
			{
				"name": "yieldAmount",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			},
			{
				"name": "timestamp",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "YieldAccrued",
		"inputs": [
			{
				"name": "timestamp",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "YieldAutoClaimed",
		"inputs": [
			{
				"name": "user",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			},
			{
				"name": "currencyId",
				"type": "uint256",
				"indexed": true,
				"internalType": "uint256"
			},
			{
				"name": "timestamp",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "YieldDistributed",
		"inputs": [
			{
				"name": "underlyingToken",
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
			},
			{
				"name": "yieldPerToken",
				"type": "uint256",
				"indexed": false,
				"internalType": "uint256"
			}
		],
		"anonymous": false
	},
	{
		"type": "event",
		"name": "YieldDistributorSet",
		"inputs": [
			{
				"name": "yieldDistributor",
				"type": "address",
				"indexed": true,
				"internalType": "address"
			}
		],
		"anonymous": false
	},
	{
		"type": "error",
		"name": "AlreadyInitialized",
		"inputs": []
	},
	{
		"type": "error",
		"name": "BorrowFailed",
		"inputs": []
	},
	{
		"type": "error",
		"name": "EthSentForErc20Deposit",
		"inputs": []
	},
	{
		"type": "error",
		"name": "FeeExceedsTransferAmount",
		"inputs": [
			{
				"name": "fee",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "amount",
				"type": "uint256",
				"internalType": "uint256"
			}
		]
	},
	{
		"type": "error",
		"name": "IncorrectEthAmount",
		"inputs": [
			{
				"name": "expected",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "actual",
				"type": "uint256",
				"internalType": "uint256"
			}
		]
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
				"name": "id",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "want",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "have",
				"type": "uint256",
				"internalType": "uint256"
			}
		]
	},
	{
		"type": "error",
		"name": "InvalidInitialization",
		"inputs": []
	},
	{
		"type": "error",
		"name": "InvalidRecipientAddress",
		"inputs": []
	},
	{
		"type": "error",
		"name": "InvalidSender",
		"inputs": [
			{
				"name": "expected",
				"type": "bytes32",
				"internalType": "bytes32"
			},
			{
				"name": "actual",
				"type": "bytes32",
				"internalType": "bytes32"
			}
		]
	},
	{
		"type": "error",
		"name": "InvalidTokenAddress",
		"inputs": []
	},
	{
		"type": "error",
		"name": "InvalidTokenRegistry",
		"inputs": []
	},
	{
		"type": "error",
		"name": "LendingManagerNotSet",
		"inputs": []
	},
	{
		"type": "error",
		"name": "LendingManagerSupplyFailed",
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
			},
			{
				"name": "amount",
				"type": "uint256",
				"internalType": "uint256"
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
		"name": "RepayFailed",
		"inputs": []
	},
	{
		"type": "error",
		"name": "SyntheticTokenNotFound",
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
		"name": "TargetChainNotSupported",
		"inputs": [
			{
				"name": "chainId",
				"type": "uint32",
				"internalType": "uint32"
			}
		]
	},
	{
		"type": "error",
		"name": "TokenNotSupportedForLocalDeposits",
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
		"name": "TokenRegistryNotSet",
		"inputs": []
	},
	{
		"type": "error",
		"name": "TransferError",
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
			},
			{
				"name": "amount",
				"type": "uint256",
				"internalType": "uint256"
			}
		]
	},
	{
		"type": "error",
		"name": "UnauthorizedCaller",
		"inputs": [
			{
				"name": "caller",
				"type": "address",
				"internalType": "address"
			}
		]
	},
	{
		"type": "error",
		"name": "UnauthorizedOperator",
		"inputs": [
			{
				"name": "operator",
				"type": "address",
				"internalType": "address"
			}
		]
	},
	{
		"type": "error",
		"name": "UnknownMessageType",
		"inputs": []
	},
	{
		"type": "error",
		"name": "UnknownOriginChain",
		"inputs": [
			{
				"name": "chainId",
				"type": "uint32",
				"internalType": "uint32"
			}
		]
	},
	{
		"type": "error",
		"name": "YieldAccrualFailed",
		"inputs": []
	},
	{
		"type": "error",
		"name": "YieldClaimFailed",
		"inputs": []
	},
	{
		"type": "error",
		"name": "ZeroAmount",
		"inputs": []
	}
] as const;