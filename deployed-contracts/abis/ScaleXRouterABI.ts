export const ScaleXRouterABI: any[] = [
	{
		"type": "constructor",
		"inputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "batchCancelOrders",
		"inputs": [
			{
				"name": "",
				"type": "tuple",
				"internalType": "struct IPoolManager.Pool",
				"components": [
					{
						"name": "baseCurrency",
						"type": "address",
						"internalType": "Currency"
					},
					{
						"name": "quoteCurrency",
						"type": "address",
						"internalType": "Currency"
					},
					{
						"name": "orderBook",
						"type": "address",
						"internalType": "contract IOrderBook"
					}
				]
			},
			{
				"name": "",
				"type": "uint48[]",
				"internalType": "uint48[]"
			}
		],
		"outputs": [],
		"stateMutability": "pure"
	},
	{
		"type": "function",
		"name": "borrow",
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
		"name": "calculateMinOutAmountForMarket",
		"inputs": [
			{
				"name": "pool",
				"type": "tuple",
				"internalType": "struct IPoolManager.Pool",
				"components": [
					{
						"name": "baseCurrency",
						"type": "address",
						"internalType": "Currency"
					},
					{
						"name": "quoteCurrency",
						"type": "address",
						"internalType": "Currency"
					},
					{
						"name": "orderBook",
						"type": "address",
						"internalType": "contract IOrderBook"
					}
				]
			},
			{
				"name": "inputAmount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "side",
				"type": "uint8",
				"internalType": "enum IOrderBook.Side"
			},
			{
				"name": "slippageToleranceBps",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"outputs": [
			{
				"name": "minOutputAmount",
				"type": "uint128",
				"internalType": "uint128"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "calculateMinOutForSwap",
		"inputs": [
			{
				"name": "srcCurrency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "dstCurrency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "inputAmount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "slippageToleranceBps",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"outputs": [
			{
				"name": "minOutputAmount",
				"type": "uint128",
				"internalType": "uint128"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "cancelOrder",
		"inputs": [
			{
				"name": "pool",
				"type": "tuple",
				"internalType": "struct IPoolManager.Pool",
				"components": [
					{
						"name": "baseCurrency",
						"type": "address",
						"internalType": "Currency"
					},
					{
						"name": "quoteCurrency",
						"type": "address",
						"internalType": "Currency"
					},
					{
						"name": "orderBook",
						"type": "address",
						"internalType": "contract IOrderBook"
					}
				]
			},
			{
				"name": "orderId",
				"type": "uint48",
				"internalType": "uint48"
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
		"name": "getAvailableLiquidity",
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
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getBestPrice",
		"inputs": [
			{
				"name": "_baseCurrency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "_quoteCurrency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "side",
				"type": "uint8",
				"internalType": "enum IOrderBook.Side"
			}
		],
		"outputs": [
			{
				"name": "",
				"type": "tuple",
				"internalType": "struct IOrderBook.PriceVolume",
				"components": [
					{
						"name": "price",
						"type": "uint128",
						"internalType": "uint128"
					},
					{
						"name": "volume",
						"type": "uint256",
						"internalType": "uint256"
					}
				]
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getGeneratedInterest",
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
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getHealthFactor",
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
		"name": "getNextBestPrices",
		"inputs": [
			{
				"name": "pool",
				"type": "tuple",
				"internalType": "struct IPoolManager.Pool",
				"components": [
					{
						"name": "baseCurrency",
						"type": "address",
						"internalType": "Currency"
					},
					{
						"name": "quoteCurrency",
						"type": "address",
						"internalType": "Currency"
					},
					{
						"name": "orderBook",
						"type": "address",
						"internalType": "contract IOrderBook"
					}
				]
			},
			{
				"name": "side",
				"type": "uint8",
				"internalType": "enum IOrderBook.Side"
			},
			{
				"name": "price",
				"type": "uint128",
				"internalType": "uint128"
			},
			{
				"name": "count",
				"type": "uint8",
				"internalType": "uint8"
			}
		],
		"outputs": [
			{
				"name": "",
				"type": "tuple[]",
				"internalType": "struct IOrderBook.PriceVolume[]",
				"components": [
					{
						"name": "price",
						"type": "uint128",
						"internalType": "uint128"
					},
					{
						"name": "volume",
						"type": "uint256",
						"internalType": "uint256"
					}
				]
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getOrder",
		"inputs": [
			{
				"name": "_baseCurrency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "_quoteCurrency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "orderId",
				"type": "uint48",
				"internalType": "uint48"
			}
		],
		"outputs": [
			{
				"name": "",
				"type": "tuple",
				"internalType": "struct IOrderBook.Order",
				"components": [
					{
						"name": "user",
						"type": "address",
						"internalType": "address"
					},
					{
						"name": "id",
						"type": "uint48",
						"internalType": "uint48"
					},
					{
						"name": "next",
						"type": "uint48",
						"internalType": "uint48"
					},
					{
						"name": "quantity",
						"type": "uint128",
						"internalType": "uint128"
					},
					{
						"name": "filled",
						"type": "uint128",
						"internalType": "uint128"
					},
					{
						"name": "price",
						"type": "uint128",
						"internalType": "uint128"
					},
					{
						"name": "prev",
						"type": "uint48",
						"internalType": "uint48"
					},
					{
						"name": "expiry",
						"type": "uint48",
						"internalType": "uint48"
					},
					{
						"name": "status",
						"type": "uint8",
						"internalType": "enum IOrderBook.Status"
					},
					{
						"name": "orderType",
						"type": "uint8",
						"internalType": "enum IOrderBook.OrderType"
					},
					{
						"name": "side",
						"type": "uint8",
						"internalType": "enum IOrderBook.Side"
					},
					{
						"name": "autoRepay",
						"type": "bool",
						"internalType": "bool"
					},
					{
						"name": "autoBorrow",
						"type": "bool",
						"internalType": "bool"
					}
				]
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getOrderQueue",
		"inputs": [
			{
				"name": "_baseCurrency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "_quoteCurrency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "side",
				"type": "uint8",
				"internalType": "enum IOrderBook.Side"
			},
			{
				"name": "price",
				"type": "uint128",
				"internalType": "uint128"
			}
		],
		"outputs": [
			{
				"name": "orderCount",
				"type": "uint48",
				"internalType": "uint48"
			},
			{
				"name": "totalVolume",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"stateMutability": "view"
	},
	{
		"type": "function",
		"name": "getUserDebt",
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
		"name": "getUserSupply",
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
		"name": "initialize",
		"inputs": [
			{
				"name": "_poolManager",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "_balanceManager",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "initializeWithLending",
		"inputs": [
			{
				"name": "_poolManager",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "_balanceManager",
				"type": "address",
				"internalType": "address"
			},
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
		"name": "liquidate",
		"inputs": [
			{
				"name": "borrower",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "debtToken",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "collateralToken",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "debtToCover",
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
		"name": "placeLimitOrder",
		"inputs": [
			{
				"name": "pool",
				"type": "tuple",
				"internalType": "struct IPoolManager.Pool",
				"components": [
					{
						"name": "baseCurrency",
						"type": "address",
						"internalType": "Currency"
					},
					{
						"name": "quoteCurrency",
						"type": "address",
						"internalType": "Currency"
					},
					{
						"name": "orderBook",
						"type": "address",
						"internalType": "contract IOrderBook"
					}
				]
			},
			{
				"name": "_price",
				"type": "uint128",
				"internalType": "uint128"
			},
			{
				"name": "_quantity",
				"type": "uint128",
				"internalType": "uint128"
			},
			{
				"name": "_side",
				"type": "uint8",
				"internalType": "enum IOrderBook.Side"
			},
			{
				"name": "_timeInForce",
				"type": "uint8",
				"internalType": "enum IOrderBook.TimeInForce"
			},
			{
				"name": "depositAmount",
				"type": "uint128",
				"internalType": "uint128"
			}
		],
		"outputs": [
			{
				"name": "orderId",
				"type": "uint48",
				"internalType": "uint48"
			}
		],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "placeLimitOrderWithFlags",
		"inputs": [
			{
				"name": "pool",
				"type": "tuple",
				"internalType": "struct IPoolManager.Pool",
				"components": [
					{
						"name": "baseCurrency",
						"type": "address",
						"internalType": "Currency"
					},
					{
						"name": "quoteCurrency",
						"type": "address",
						"internalType": "Currency"
					},
					{
						"name": "orderBook",
						"type": "address",
						"internalType": "contract IOrderBook"
					}
				]
			},
			{
				"name": "_price",
				"type": "uint128",
				"internalType": "uint128"
			},
			{
				"name": "_quantity",
				"type": "uint128",
				"internalType": "uint128"
			},
			{
				"name": "_side",
				"type": "uint8",
				"internalType": "enum IOrderBook.Side"
			},
			{
				"name": "_timeInForce",
				"type": "uint8",
				"internalType": "enum IOrderBook.TimeInForce"
			},
			{
				"name": "depositAmount",
				"type": "uint128",
				"internalType": "uint128"
			},
			{
				"name": "autoRepay",
				"type": "bool",
				"internalType": "bool"
			},
			{
				"name": "autoBorrow",
				"type": "bool",
				"internalType": "bool"
			}
		],
		"outputs": [
			{
				"name": "orderId",
				"type": "uint48",
				"internalType": "uint48"
			}
		],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "placeMarketOrder",
		"inputs": [
			{
				"name": "pool",
				"type": "tuple",
				"internalType": "struct IPoolManager.Pool",
				"components": [
					{
						"name": "baseCurrency",
						"type": "address",
						"internalType": "Currency"
					},
					{
						"name": "quoteCurrency",
						"type": "address",
						"internalType": "Currency"
					},
					{
						"name": "orderBook",
						"type": "address",
						"internalType": "contract IOrderBook"
					}
				]
			},
			{
				"name": "_quantity",
				"type": "uint128",
				"internalType": "uint128"
			},
			{
				"name": "_side",
				"type": "uint8",
				"internalType": "enum IOrderBook.Side"
			},
			{
				"name": "depositAmount",
				"type": "uint128",
				"internalType": "uint128"
			},
			{
				"name": "minOutAmount",
				"type": "uint128",
				"internalType": "uint128"
			}
		],
		"outputs": [
			{
				"name": "orderId",
				"type": "uint48",
				"internalType": "uint48"
			},
			{
				"name": "filled",
				"type": "uint128",
				"internalType": "uint128"
			}
		],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "placeMarketOrder",
		"inputs": [
			{
				"name": "pool",
				"type": "tuple",
				"internalType": "struct IPoolManager.Pool",
				"components": [
					{
						"name": "baseCurrency",
						"type": "address",
						"internalType": "Currency"
					},
					{
						"name": "quoteCurrency",
						"type": "address",
						"internalType": "Currency"
					},
					{
						"name": "orderBook",
						"type": "address",
						"internalType": "contract IOrderBook"
					}
				]
			},
			{
				"name": "_quantity",
				"type": "uint128",
				"internalType": "uint128"
			},
			{
				"name": "_side",
				"type": "uint8",
				"internalType": "enum IOrderBook.Side"
			},
			{
				"name": "depositAmount",
				"type": "uint128",
				"internalType": "uint128"
			},
			{
				"name": "minOutAmount",
				"type": "uint128",
				"internalType": "uint128"
			},
			{
				"name": "autoRepay",
				"type": "bool",
				"internalType": "bool"
			},
			{
				"name": "autoBorrow",
				"type": "bool",
				"internalType": "bool"
			}
		],
		"outputs": [
			{
				"name": "orderId",
				"type": "uint48",
				"internalType": "uint48"
			},
			{
				"name": "filled",
				"type": "uint128",
				"internalType": "uint128"
			}
		],
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
		"name": "repay",
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
		"name": "swap",
		"inputs": [
			{
				"name": "srcCurrency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "dstCurrency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "srcAmount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "minDstAmount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "maxHops",
				"type": "uint8",
				"internalType": "uint8"
			},
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "depositAmount",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"outputs": [
			{
				"name": "receivedAmount",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "swap",
		"inputs": [
			{
				"name": "srcCurrency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "dstCurrency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "srcAmount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "minDstAmount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "maxHops",
				"type": "uint8",
				"internalType": "uint8"
			},
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			}
		],
		"outputs": [
			{
				"name": "receivedAmount",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
		"stateMutability": "nonpayable"
	},
	{
		"type": "function",
		"name": "swap",
		"inputs": [
			{
				"name": "srcCurrency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "dstCurrency",
				"type": "address",
				"internalType": "Currency"
			},
			{
				"name": "srcAmount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "minDstAmount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "maxHops",
				"type": "uint8",
				"internalType": "uint8"
			},
			{
				"name": "user",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "depositAmount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "keepInBalance",
				"type": "bool",
				"internalType": "bool"
			}
		],
		"outputs": [
			{
				"name": "receivedAmount",
				"type": "uint256",
				"internalType": "uint256"
			}
		],
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
		"name": "withdraw",
		"inputs": [
			{
				"name": "",
				"type": "address",
				"internalType": "Currency"
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
		"type": "error",
		"name": "AlreadyInitialized",
		"inputs": []
	},
	{
		"type": "error",
		"name": "BalanceManagerNotSet",
		"inputs": []
	},
	{
		"type": "error",
		"name": "BorrowFailed",
		"inputs": []
	},
	{
		"type": "error",
		"name": "DepositFailed",
		"inputs": []
	},
	{
		"type": "error",
		"name": "FillOrKillNotFulfilled",
		"inputs": [
			{
				"name": "filledAmount",
				"type": "uint128",
				"internalType": "uint128"
			},
			{
				"name": "requestedAmount",
				"type": "uint128",
				"internalType": "uint128"
			}
		]
	},
	{
		"type": "error",
		"name": "IdenticalCurrencies",
		"inputs": [
			{
				"name": "currency",
				"type": "address",
				"internalType": "address"
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
		"name": "InsufficientBalanceRequired",
		"inputs": [
			{
				"name": "requiredDeposit",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "userBalance",
				"type": "uint256",
				"internalType": "uint256"
			}
		]
	},
	{
		"type": "error",
		"name": "InsufficientHealthFactorForBorrow",
		"inputs": [
			{
				"name": "projected",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "minimum",
				"type": "uint256",
				"internalType": "uint256"
			}
		]
	},
	{
		"type": "error",
		"name": "InsufficientOrderBalance",
		"inputs": [
			{
				"name": "available",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "required",
				"type": "uint256",
				"internalType": "uint256"
			}
		]
	},
	{
		"type": "error",
		"name": "InsufficientSwapBalance",
		"inputs": [
			{
				"name": "available",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "required",
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
		"name": "InvalidOrderType",
		"inputs": []
	},
	{
		"type": "error",
		"name": "InvalidPrice",
		"inputs": [
			{
				"name": "price",
				"type": "uint256",
				"internalType": "uint256"
			}
		]
	},
	{
		"type": "error",
		"name": "InvalidPriceIncrement",
		"inputs": []
	},
	{
		"type": "error",
		"name": "InvalidQuantity",
		"inputs": []
	},
	{
		"type": "error",
		"name": "InvalidQuantityIncrement",
		"inputs": []
	},
	{
		"type": "error",
		"name": "InvalidRecipientAddress",
		"inputs": []
	},
	{
		"type": "error",
		"name": "InvalidRouter",
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
		"name": "InvalidSideForQuoteAmount",
		"inputs": []
	},
	{
		"type": "error",
		"name": "InvalidSlippageTolerance",
		"inputs": [
			{
				"name": "slippageBps",
				"type": "uint256",
				"internalType": "uint256"
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
		"name": "InvalidTradingRule",
		"inputs": [
			{
				"name": "reason",
				"type": "string",
				"internalType": "string"
			}
		]
	},
	{
		"type": "error",
		"name": "LendingManagerNotSet",
		"inputs": []
	},
	{
		"type": "error",
		"name": "LiquidationFailed",
		"inputs": []
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
		"name": "NegativeSpreadCreated",
		"inputs": [
			{
				"name": "bestBid",
				"type": "uint128",
				"internalType": "uint128"
			},
			{
				"name": "bestAsk",
				"type": "uint128",
				"internalType": "uint128"
			}
		]
	},
	{
		"type": "error",
		"name": "NoValidSwapPath",
		"inputs": [
			{
				"name": "srcCurrency",
				"type": "address",
				"internalType": "address"
			},
			{
				"name": "dstCurrency",
				"type": "address",
				"internalType": "address"
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
		"name": "OrderHasNoLiquidity",
		"inputs": []
	},
	{
		"type": "error",
		"name": "OrderIsNotOpenOrder",
		"inputs": [
			{
				"name": "status",
				"type": "uint8",
				"internalType": "uint8"
			}
		]
	},
	{
		"type": "error",
		"name": "OrderNotFound",
		"inputs": []
	},
	{
		"type": "error",
		"name": "OrderTooLarge",
		"inputs": [
			{
				"name": "amount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "maxAmount",
				"type": "uint256",
				"internalType": "uint256"
			}
		]
	},
	{
		"type": "error",
		"name": "OrderTooSmall",
		"inputs": [
			{
				"name": "amount",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "minAmount",
				"type": "uint256",
				"internalType": "uint256"
			}
		]
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
		"name": "PoolAlreadyExists",
		"inputs": [
			{
				"name": "id",
				"type": "bytes32",
				"internalType": "bytes32"
			}
		]
	},
	{
		"type": "error",
		"name": "PostOnlyWouldTake",
		"inputs": []
	},
	{
		"type": "error",
		"name": "QueueEmpty",
		"inputs": []
	},
	{
		"type": "error",
		"name": "RepayFailed",
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
		"name": "SlippageExceeded",
		"inputs": [
			{
				"name": "requestedPrice",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "limitPrice",
				"type": "uint256",
				"internalType": "uint256"
			}
		]
	},
	{
		"type": "error",
		"name": "SlippageTooHigh",
		"inputs": [
			{
				"name": "received",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "minReceived",
				"type": "uint256",
				"internalType": "uint256"
			}
		]
	},
	{
		"type": "error",
		"name": "SwapHopFailed",
		"inputs": [
			{
				"name": "hopIndex",
				"type": "uint256",
				"internalType": "uint256"
			},
			{
				"name": "receivedAmount",
				"type": "uint256",
				"internalType": "uint256"
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
		"name": "TooManyHops",
		"inputs": [
			{
				"name": "maxHops",
				"type": "uint8",
				"internalType": "uint8"
			},
			{
				"name": "limit",
				"type": "uint8",
				"internalType": "uint8"
			}
		]
	},
	{
		"type": "error",
		"name": "TradingPaused",
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
		"name": "UnauthorizedCancellation",
		"inputs": []
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
		"name": "UnauthorizedRouter",
		"inputs": [
			{
				"name": "reouter",
				"type": "address",
				"internalType": "address"
			}
		]
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
		"name": "ZeroAmount",
		"inputs": []
	}
] as const;