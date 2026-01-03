// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
import {IMailbox} from "./interfaces/IMailbox.sol";
import {IMessageRecipient} from "./interfaces/IMessageRecipient.sol";
import {Currency} from "./libraries/Currency.sol";

import {HyperlaneMessages} from "./libraries/HyperlaneMessages.sol";
import {BalanceManagerStorage} from "./storages/BalanceManagerStorage.sol";

import {TokenRegistry} from "./TokenRegistry.sol";
import {ISyntheticERC20} from "./interfaces/ISyntheticERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";

// Constants for yield calculations
uint256 constant PRECISION = 1e18;
uint256 constant BASIS_POINTS = 10000;

contract BalanceManager is
    IBalanceManager,
    IMessageRecipient,
    BalanceManagerStorage,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // Custom errors (unique to BalanceManager)
    error IncorrectEthAmount(uint256 expected, uint256 actual);
    error EthSentForErc20Deposit();
    error FeeExceedsTransferAmount(uint256 fee, uint256 amount);
    error YieldClaimFailed();
    error YieldAccrualFailed();
    error UnknownMessageType();
    error SyntheticTokenNotFound(address token);
    // Lending errors
    error LendingManagerNotSet();
    error BorrowFailed();
    error RepayFailed();
    error LendingManagerSupplyFailed(address user, address token, uint256 amount);
    // Core errors from IBalanceManagerErrors
    error InsufficientBalance(address user, uint256 id, uint256 want, uint256 have);
    error TransferError(address user, Currency currency, uint256 amount);
    error ZeroAmount();
    error UnauthorizedOperator(address operator);
    error UnauthorizedCaller(address caller);
    error InvalidTokenAddress();
    error InvalidRecipientAddress();
    error TokenRegistryNotSet();
    error TokenNotSupportedForLocalDeposits(address token);
    error AlreadyInitialized();
    error OnlyMailbox();
    error UnknownOriginChain(uint32 chainId);
    error InvalidSender(bytes32 expected, bytes32 actual);
    error MessageAlreadyProcessed(bytes32 messageId);
    error TargetChainNotSupported(uint32 chainId);
    error InvalidTokenRegistry();
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _feeReceiver,
        uint256 _feeMaker,
        uint256 _feeTaker
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        Storage storage $ = getStorage();
        $.feeReceiver = _feeReceiver;
        $.feeMaker = _feeMaker;
        $.feeTaker = _feeTaker;
        $.feeUnit = 1000;
    }

    function setPoolManager(
        address _poolManager
    ) external onlyOwner {
        getStorage().poolManager = _poolManager;
        emit PoolManagerSet(_poolManager);
    }

    function setMailbox(
        address _mailbox
    ) external onlyOwner {
        getStorage().mailbox = _mailbox;
    }

    // Allow owner to set authorized operators (e.g., Router)
    function setAuthorizedOperator(address operator, bool approved) external {
        Storage storage $ = getStorage();

        if (msg.sender != owner() && msg.sender != $.poolManager) {
            revert UnauthorizedCaller(msg.sender);
        }

        $.authorizedOperators[operator] = approved;
        emit OperatorSet(operator, approved);
    }

    /// @notice Add authorized operator (alias for setAuthorizedOperator)
    function addAuthorizedOperator(address operator) external {
        Storage storage $ = getStorage();

        if (msg.sender != owner() && msg.sender != $.poolManager) {
            revert UnauthorizedCaller(msg.sender);
        }

        $.authorizedOperators[operator] = true;
        emit OperatorSet(operator, true);
    }

    function setFees(uint256 _feeMaker, uint256 _feeTaker) external onlyOwner {
        Storage storage $ = getStorage();
        $.feeMaker = _feeMaker;
        $.feeTaker = _feeTaker;
    }

    /// @notice Resolve currency to use synthetic token's ID if available
    /// @dev This ensures consistent balance tracking - all balances are stored under synthetic token IDs
    /// @param currency The currency to resolve
    /// @return The currency ID to use for balance tracking
    function _resolveCurrencyId(Currency currency) internal view returns (uint256) {
        Storage storage $ = getStorage();
        address tokenAddr = Currency.unwrap(currency);
        address syntheticToken = $.syntheticTokens[tokenAddr];

        // If this is an underlying token with a synthetic, use synthetic's ID
        // If this is already a synthetic token or no mapping exists, use as-is
        return syntheticToken != address(0)
            ? Currency.wrap(syntheticToken).toId()
            : currency.toId();
    }

    // Allow anyone to check balanceOf
    function getBalance(address user, Currency currency) external view returns (uint256) {
        return getStorage().balanceOf[user][_resolveCurrencyId(currency)];
    }

    function getLockedBalance(address user, address operator, Currency currency) external view returns (uint256) {
        return getStorage().lockedBalanceOf[user][operator][_resolveCurrencyId(currency)];
    }

    function deposit(Currency currency, uint256 amount, address sender, address user) public payable nonReentrant returns (uint256) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();
        if (msg.sender != sender && !$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        if (currency.isAddressZero()) {
            if (msg.value != amount) {
                revert IncorrectEthAmount(amount, msg.value);
            }
        } else {
            if (msg.value != 0) {
                revert EthSentForErc20Deposit();
            }

            currency.transferFrom(sender, address(this), amount);
        }

        address tokenAddr = Currency.unwrap(currency);

        // Only use existing synthetic tokens - don't create new ones automatically
        if ($.syntheticTokens[tokenAddr] == address(0)) {
            revert TokenNotSupportedForLocalDeposits(tokenAddr);
        }

        address syntheticToken = $.syntheticTokens[tokenAddr];

        // Deposit underlying tokens to unified liquidity pool in LendingManager
        // Track user's individual position in the unified pool
        if ($.lendingManager != address(0)) {
            // Approve lending manager to spend tokens
            IERC20(tokenAddr).approve($.lendingManager, amount);

            // Call LendingManager to deposit under the user's address for yield management
            ILendingManager($.lendingManager).supplyForUser(user, tokenAddr, amount);
            // If lending manager deposit fails, tokens remain in contract
        }

        // Mint synthetic tokens to BalanceManager (vault) to represent underlying assets
        ISyntheticERC20(syntheticToken).mint(address(this), amount);

        // Update internal balance for trading (synthetic token's currency ID)
        uint256 currencyId = _resolveCurrencyId(currency);

        unchecked {
            $.balanceOf[user][currencyId] += amount;
            // Track total internal supply for yield calculations
            $.totalInternalSupply[syntheticToken] += amount;
        }

        emit Deposit(user, currencyId, amount);
        return amount;
    }

    function depositAndLock(
        Currency currency,
        uint256 amount,
        address user,
        address orderBook
    ) external nonReentrant returns (uint256) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();

        // Verify if the caller is the user or an authorized operator
        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        // Transfer tokens directly from sender to this contract
        currency.transferFrom(user, address(this), amount);

        // Credit directly to locked balance, bypassing the regular balance
        uint256 currencyId = _resolveCurrencyId(currency);

        unchecked {
            $.lockedBalanceOf[user][orderBook][currencyId] += amount;
        }

        emit Deposit(user, currencyId, amount);

        return amount;
    }

    function withdraw(Currency currency, uint256 amount) external {
        withdraw(currency, amount, msg.sender);
    }

    // Withdraw tokens - ALWAYS claims accumulated yield
    function withdraw(Currency currency, uint256 amount, address user) public nonReentrant returns (uint256 totalAmount) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();
        // Verify if the caller is the user or an authorized operator
        if (msg.sender != user && !$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        address tokenAddr = Currency.unwrap(currency);
        address syntheticToken = $.syntheticTokens[tokenAddr];

        // Use resolved currency ID (synthetic token's ID for underlying tokens)
        uint256 currencyId = _resolveCurrencyId(currency);
        uint256 availableBalance = $.balanceOf[user][currencyId];
        
        if (availableBalance < amount) {
            revert InsufficientBalance(user, currencyId, amount, availableBalance);
        }
        
        // ALWAYS calculate and claim yield on withdrawal
        if (syntheticToken != address(0)) {
            // Calculate ALL accumulated yield (inline to avoid function ordering issues)
            // Use internal balance tracking since tokens are held in the vault
            uint256 userBalance = $.balanceOf[user][currencyId];
            uint256 yieldAmount = 0;
            address underlyingToken = tokenAddr;
            
            if (userBalance > 0 && underlyingToken != address(0)) {
                uint256 currentYieldPerToken = $.yieldPerToken[underlyingToken];
                uint256 userCheckpoint = $.userYieldCheckpoints[user][syntheticToken];
                
                // Defensive programming: ensure we don't have underflow
                if (currentYieldPerToken >= userCheckpoint && userBalance > 0) {
                    // Additional check to prevent overflow in multiplication
                    uint256 yieldDiff = currentYieldPerToken - userCheckpoint;
                    if (yieldDiff > 0) {
                        // Use manual overflow check with safer calculation
                        // Calculate yieldAmount = (userBalance * yieldDiff) / PRECISION
                        if (userBalance == 0) {
                            yieldAmount = 0;
                        } else {
                            // Use division-first approach to prevent overflow
                            // yieldAmount = userBalance * (yieldDiff / PRECISION) + (userBalance * (yieldDiff % PRECISION)) / PRECISION
                            uint256 yieldDiffWhole = yieldDiff / PRECISION;
                            uint256 yieldDiffRemainder = yieldDiff % PRECISION;
                            
                            yieldAmount = userBalance * yieldDiffWhole;
                            
                            // Add the fractional part safely
                            if (yieldDiffRemainder > 0 && userBalance < type(uint256).max / yieldDiffRemainder) {
                                uint256 fractionalPart = (userBalance * yieldDiffRemainder) / PRECISION;
                                yieldAmount += fractionalPart;
                            }
                        }
                    }
                }
                
                // CRITICAL: Update checkpoint AFTER calculating yield (reentrancy protection)
                // This ensures yield is only claimed once
                if (currentYieldPerToken > userCheckpoint) {
                    $.userYieldCheckpoints[user][syntheticToken] = currentYieldPerToken;
                }
            }
            
            // Calculate total withdrawal amount (principal + ALL accumulated yield)
            // Safety check for overflow
            totalAmount = amount;
            if (yieldAmount > 0 && totalAmount < type(uint256).max - yieldAmount) {
                totalAmount += yieldAmount;
            }
            
            // Withdraw from LendingManager, but check available liquidity first
            if ($.lendingManager != address(0)) {
                // Check available liquidity in LendingManager for principal only
                uint256 availableLiquidity = _getAvailableLiquidity(underlyingToken);
                
                // Only withdraw principal amount, limited by available liquidity
                uint256 principalToWithdraw = amount > availableLiquidity ? availableLiquidity : amount;
                
                if (principalToWithdraw > 0) {
                    (uint256 withdrawnAmount, ) = ILendingManager($.lendingManager).withdrawLiquidity(underlyingToken, principalToWithdraw, user);
                    totalAmount = withdrawnAmount;
                }
                
                // Withdraw yield separately if there is any
                if (yieldAmount > 0) {
                    _withdrawYield(underlyingToken, yieldAmount);
                    // Add yield to total amount if withdrawal succeeded
                    if (totalAmount < type(uint256).max - yieldAmount) {
                        totalAmount += yieldAmount;
                    }
                }
            }
            
            // Transfer amount in underlying tokens to user (adjusted based on available liquidity)
            // Safety: ensure totalAmount is reasonable and contract has sufficient balance
            if (totalAmount > 0 && totalAmount <= type(uint256).max / 2) {
                uint256 contractBalance = IERC20(underlyingToken).balanceOf(address(this));
                if (contractBalance >= totalAmount) {
                    IERC20(underlyingToken).transfer(user, totalAmount);
                }
            }

            // Note: We don't burn synthetic tokens - internal balance IS the ownership.
            // Synthetic tokens are not minted during deposit, so nothing to burn.

            // Update internal balance tracking
            $.balanceOf[user][currencyId] -= amount;
            // Update total internal supply for yield calculations
            $.totalInternalSupply[syntheticToken] -= amount;

            // Clean up checkpoint if user will have zero balance
            uint256 remainingBalance = $.balanceOf[user][currencyId];
            if (remainingBalance == 0 && syntheticToken != address(0)) {
                delete $.userYieldCheckpoints[user][syntheticToken];
            }
            
            // Emit event with safety checks
            uint256 yieldToEmit = yieldAmount <= totalAmount ? yieldAmount : 0;
            emit WithdrawalWithYield(user, currencyId, amount, yieldToEmit, remainingBalance);
        } else {
            // No synthetic token case - regular withdrawal
            totalAmount = amount;
            $.balanceOf[user][currencyId] -= amount;
            currency.transfer(user, amount);
            emit Withdrawal(user, currencyId, amount);
        }
        
        return totalAmount;
    }

    function lock(address user, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();

        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        _lock(user, currency, amount, msg.sender);
    }

    function lock(address user, Currency currency, uint256 amount, address orderBook) external {
        Storage storage $ = getStorage();

        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        _lock(user, currency, amount, orderBook);
    }

    function _lock(address user, Currency currency, uint256 amount, address locker) private {
        Storage storage $ = getStorage();
        uint256 currencyId = _resolveCurrencyId(currency);

        if ($.balanceOf[user][currencyId] < amount) {
            revert InsufficientBalance(user, currencyId, amount, $.balanceOf[user][currencyId]);
        }

        $.balanceOf[user][currencyId] -= amount;
        $.lockedBalanceOf[user][locker][currencyId] += amount;

        emit Lock(user, currencyId, amount);
    }

    function unlock(address user, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();
        uint256 currencyId = _resolveCurrencyId(currency);

        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        if ($.lockedBalanceOf[user][msg.sender][currencyId] < amount) {
            revert InsufficientBalance(
                user, currencyId, amount, $.lockedBalanceOf[user][msg.sender][currencyId]
            );
        }

        // Step 1: ALWAYS claim accumulated yield for the user's synthetic tokens
        // This applies to both order cancellation and order matching
        _claimUserYield(user);

        // Step 2: Return funds to user's balance (same currency)
        $.balanceOf[user][currencyId] += amount;

        // Step 3: Reduce locked balance
        $.lockedBalanceOf[user][msg.sender][currencyId] -= amount;

        emit Unlock(user, currencyId, amount);
        emit YieldAutoClaimed(user, currencyId, block.timestamp);
    }

    // unlockWithYield function removed - unlock() now always claims yield

    
    function transferOut(address sender, address receiver, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();
        uint256 currencyId = _resolveCurrencyId(currency);

        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if ($.balanceOf[sender][currencyId] < amount) {
            revert InsufficientBalance(sender, currencyId, amount, $.balanceOf[sender][currencyId]);
        }

        currency.transfer(receiver, amount);

        $.balanceOf[sender][currencyId] -= amount;
    }

    function transferLockedFrom(address sender, address receiver, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();
        uint256 currencyId = _resolveCurrencyId(currency);

        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if ($.lockedBalanceOf[sender][msg.sender][currencyId] < amount) {
            revert InsufficientBalance(
                sender, currencyId, amount, $.lockedBalanceOf[sender][msg.sender][currencyId]
            );
        }

        // Determine fee based on the role (maker/taker)
        uint256 feeAmount = amount * $.feeTaker / _feeUnit();
        if (feeAmount > amount) {
            revert FeeExceedsTransferAmount(feeAmount, amount);
        }

        // Deduct fee and update balances
        $.lockedBalanceOf[sender][msg.sender][currencyId] -= amount;
        uint256 amountAfterFee = amount - feeAmount;
        $.balanceOf[receiver][currencyId] += amountAfterFee;

        // Transfer the fee to the feeReceiver
        $.balanceOf[$.feeReceiver][currencyId] += feeAmount;

        // Note: LendingManager supply tracking is no longer needed here.
        // Supply ownership is determined by gsToken balance directly.

        emit TransferLockedFrom(msg.sender, sender, receiver, currencyId, amount, feeAmount);
    }

    function transferFrom(address sender, address receiver, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();
        uint256 currencyId = _resolveCurrencyId(currency);

        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if ($.balanceOf[sender][currencyId] < amount) {
            revert InsufficientBalance(sender, currencyId, amount, $.balanceOf[sender][currencyId]);
        }

        // Determine fee based on the role (maker/taker)
        uint256 feeAmount = amount * $.feeMaker / _feeUnit();
        if (feeAmount > amount) {
            revert FeeExceedsTransferAmount(feeAmount, amount);
        }

        // Deduct fee and update balances
        $.balanceOf[sender][currencyId] -= amount;
        uint256 amountAfterFee = amount - feeAmount;
        $.balanceOf[receiver][currencyId] += amountAfterFee;

        // Transfer the fee to the feeReceiver
        $.balanceOf[$.feeReceiver][currencyId] += feeAmount;

        // Note: LendingManager supply tracking is no longer needed here.
        // Supply ownership is determined by gsToken balance directly.

        emit TransferFrom(msg.sender, sender, receiver, currencyId, amount, feeAmount);
    }

    // Add public getters for fees and feeReceiver
    function feeMaker() external view returns (uint256) {
        return getStorage().feeMaker;
    }

    function feeTaker() external view returns (uint256) {
        return getStorage().feeTaker;
    }

    function feeReceiver() external view returns (address) {
        return getStorage().feeReceiver;
    }

    function getFeeUnit() external pure returns (uint256) {
        return 1000;
    }

    function _feeUnit() private view returns (uint256) {
        return getStorage().feeUnit;
    }

    // =============================================================
    //                   SYNTHETIC TOKEN FUNCTIONS
    // =============================================================

    /// @notice Get the synthetic token address for a real token
    function getSyntheticToken(address realToken) external view returns (address) {
        return getStorage().syntheticTokens[realToken];
    }

    /// @notice Add a supported asset for lending
    function addSupportedAsset(address realToken, address syntheticToken) external onlyOwner {
        Storage storage $ = getStorage();
        bool wasSupported = $.supportedAssets[realToken];
        
        $.syntheticTokens[realToken] = syntheticToken;
        $.supportedAssets[realToken] = true;
        
        // Add to list if not already there
        if (!wasSupported) {
            $.supportedAssetsList.push(realToken);
        }
        
        emit AssetAdded(realToken, syntheticToken);
    }

    /// @notice Remove a supported asset
    function removeSupportedAsset(address realToken) external onlyOwner {
        Storage storage $ = getStorage();
        $.supportedAssets[realToken] = false;
        emit AssetRemoved(realToken);
    }

    /// @notice Check if an asset is supported
    function isAssetSupported(address realToken) external view returns (bool) {
        return getStorage().supportedAssets[realToken];
    }

    /// @notice Set the lending manager address
    function setLendingManager(address _lendingManager) external onlyOwner {
        getStorage().lendingManager = _lendingManager;
        emit LendingManagerSet(_lendingManager);
    }

    /// @notice Get the lending manager address
    function getLendingManager() external view returns (address) {
        return getStorage().lendingManager;
    }

    /// @notice Alias for getLendingManager to match interface
    function lendingManager() external view returns (address) {
        return getStorage().lendingManager;
    }

    /// @notice Set the token factory address
    function setTokenFactory(address _tokenFactory) external onlyOwner {
        getStorage().tokenFactory = _tokenFactory;
        emit TokenFactorySet(_tokenFactory);
    }

    /// @notice Get the token factory address
    function tokenFactory() external view returns (address) {
        return getStorage().tokenFactory;
    }

    /// @notice Get list of supported assets
    function getSupportedAssets() external view returns (address[] memory) {
        return getStorage().supportedAssetsList;
    }

    /// @notice Get list of supported assets (internal function)
    function _getSupportedAssets() internal view returns (address[] memory) {
        return getStorage().supportedAssetsList;
    }

    /// @notice Get underlying token for a synthetic token
    function _getUnderlyingToken(address syntheticToken) internal view returns (address) {
        Storage storage $ = getStorage();
        
        // For testing purposes, we can iterate through supported assets
        // This is NOT gas efficient for production
        address[] memory supportedAssets = _getSupportedAssets();
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            if ($.syntheticTokens[supportedAssets[i]] == syntheticToken) {
                return supportedAssets[i];
            }
        }
        
        return address(0);
    }

    /// @notice Calculate yield for a user on a specific synthetic token
    function calculateUserYield(address user, address syntheticToken) external view returns (uint256) {
        Storage storage $ = getStorage();

        // Get underlying token for this synthetic token
        address underlyingToken = _getUnderlyingToken(syntheticToken);
        if (underlyingToken == address(0)) return 0;

        // Get user's balance from internal tracking - stored under synthetic token's currency ID
        uint256 userBalance = $.balanceOf[user][Currency.wrap(syntheticToken).toId()];
        if (userBalance == 0) return 0;
        
        // Get current yield per token for this underlying token
        uint256 currentYieldPerToken = $.yieldPerToken[underlyingToken];
        
        // Get user's checkpoint (yield per token when they last claimed)
        uint256 userCheckpoint = $.userYieldCheckpoints[user][syntheticToken];
        
        // Calculate unclaimed yield with overflow protection
        uint256 unclaimedYield = 0;
        if (currentYieldPerToken > userCheckpoint) {
            uint256 yieldDiff = currentYieldPerToken - userCheckpoint;
            // Use the same safe calculation method as withdrawal
            if (userBalance > 0) {
                // Use division-first approach to prevent overflow
                uint256 yieldDiffWhole = yieldDiff / PRECISION;
                uint256 yieldDiffRemainder = yieldDiff % PRECISION;
                
                unclaimedYield = userBalance * yieldDiffWhole;
                
                // Add the fractional part safely
                if (yieldDiffRemainder > 0 && userBalance < type(uint256).max / yieldDiffRemainder) {
                    uint256 fractionalPart = (userBalance * yieldDiffRemainder) / PRECISION;
                    unclaimedYield += fractionalPart;
                }
            }
        }
        
        return unclaimedYield;
    }

    /// @notice Get available balance including yield
    function getAvailableBalance(address user, Currency currency) external view returns (uint256) {
        Storage storage $ = getStorage();
        uint256 currencyId = _resolveCurrencyId(currency);
        uint256 baseBalance = $.balanceOf[user][currencyId];

        if ($.lendingManager == address(0)) {
            return baseBalance;
        }

        // Get yield from lending manager
        try ILendingManager($.lendingManager).calculateYield(user, Currency.unwrap(currency)) returns (uint256 yieldAmount) {
            return baseBalance + yieldAmount;
        } catch {
            return baseBalance;
        }
    }

    /// @notice Accrue yield for all users (should be called periodically)
    function accrueYield() external nonReentrant {
        Storage storage $ = getStorage();
        if ($.lendingManager == address(0)) {
            revert LendingManagerNotSet();
        }
        
        // Get interest generated by LendingManager for each supported asset
        address[] memory supportedAssets = _getSupportedAssets();
        
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address underlyingToken = supportedAssets[i];
            _accrueYieldForToken(underlyingToken);
        }
        
        emit YieldAccrued(block.timestamp);
    }

    /// @notice Accrue yield for a specific token
    function _accrueYieldForToken(address underlyingToken) internal {
        Storage storage $ = getStorage();

        address syntheticToken = $.syntheticTokens[underlyingToken];
        if (syntheticToken == address(0)) return;

        // Use internal supply tracking instead of ERC20 totalSupply
        // (gsTokens are not minted to ERC20 during deposit)
        uint256 totalSupply = $.totalInternalSupply[syntheticToken];
        if (totalSupply == 0) return;
        
        uint256 interestGenerated = _getInterestGenerated(underlyingToken);
        if (interestGenerated == 0) return;
        
        uint256 availableLiquidity = _getAvailableLiquidity(underlyingToken);
        uint256 yieldToDistribute = interestGenerated > availableLiquidity ? availableLiquidity : interestGenerated;
        
        if (yieldToDistribute == 0) return;
        
        if (_withdrawYield(underlyingToken, yieldToDistribute)) {
            _distributeYield(underlyingToken, syntheticToken, yieldToDistribute, totalSupply);
        }
    }
    
    function _getInterestGenerated(address underlyingToken) internal view returns (uint256) {
        Storage storage $ = getStorage();
        try ILendingManager($.lendingManager).getGeneratedInterest(underlyingToken) returns (uint256 result) {
            return result;
        } catch {
            return 0;
        }
    }
    
    function _getAvailableLiquidity(address underlyingToken) internal view returns (uint256) {
        Storage storage $ = getStorage();
        try ILendingManager($.lendingManager).getAvailableLiquidity(underlyingToken) returns (uint256 result) {
            return result;
        } catch {
            return 0;
        }
    }
    
    function _withdrawYield(address underlyingToken, uint256 amount) internal returns (bool) {
        Storage storage $ = getStorage();
        try ILendingManager($.lendingManager).withdrawGeneratedInterest(underlyingToken, amount) {
            return true;
        } catch {
            return false;
        }
    }
    
    function _distributeYield(address underlyingToken, address syntheticToken, uint256 yieldToDistribute, uint256 totalSupply) internal {
        Storage storage $ = getStorage();
        uint256 yieldToAdd = (yieldToDistribute * PRECISION) / totalSupply;
        $.yieldPerToken[underlyingToken] += yieldToAdd;
          
        // Continue even if lending manager call fails - don't block yield distribution
        try ILendingManager($.lendingManager).updateInterestAccrual(underlyingToken) {
            // Success - continue
        } catch {
            // Failure - continue anyway, don't block yield distribution
        }
        
        emit YieldDistributed(underlyingToken, syntheticToken, yieldToDistribute, $.yieldPerToken[underlyingToken]);
    }

    /// @notice Claim all available yield for a user across all synthetic tokens
    function _claimUserYield(address user) internal {
        Storage storage $ = getStorage();
        address[] memory supportedAssets = _getSupportedAssets();
        
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address underlyingToken = supportedAssets[i];
            address syntheticToken = $.syntheticTokens[underlyingToken];
            
            if (syntheticToken != address(0)) {
                // Use internal balance tracking - balances are stored under synthetic token's currency ID
                uint256 userBalance = $.balanceOf[address(user)][Currency.wrap(syntheticToken).toId()];
                if (userBalance == 0) continue;
                
                // Get current yield per token for this underlying token
                uint256 currentYieldPerToken = $.yieldPerToken[underlyingToken];
                
                // Get user's checkpoint (yield per token when they last claimed)
                uint256 userCheckpoint = $.userYieldCheckpoints[user][syntheticToken];
                
                // Calculate unclaimed yield
                uint256 yieldAmount = (userBalance * (currentYieldPerToken - userCheckpoint)) / PRECISION;
                
                if (yieldAmount > 0) {
                    // Update user's checkpoint
                    $.userYieldCheckpoints[user][syntheticToken] = currentYieldPerToken;
                    
                    // Transfer yield to user in underlying tokens
                    IERC20(underlyingToken).transfer(user, yieldAmount);
                }
            }
        }
    }

    
    
    // =============================================================
    //                   CROSS-CHAIN FUNCTIONS
    // =============================================================

    // Initialize cross-chain functionality
    function initializeCrossChain(address _mailbox, uint32 _localDomain) external onlyOwner {
        Storage storage $ = getStorage();
        if ($.mailbox != address(0)) {
            revert AlreadyInitialized();
        }

        $.mailbox = _mailbox;
        $.localDomain = _localDomain;

        emit CrossChainInitialized(_mailbox, _localDomain);
    }

    // Update cross-chain configuration (for upgrades)
    function updateCrossChainConfig(address _mailbox, uint32 _localDomain) external onlyOwner {
        Storage storage $ = getStorage();

        address oldMailbox = $.mailbox;
        uint32 oldDomain = $.localDomain;

        $.mailbox = _mailbox;
        $.localDomain = _localDomain;

        emit CrossChainConfigUpdated(oldMailbox, _mailbox, oldDomain, _localDomain);
    }

    // Set TokenRegistry for synthetic token mapping
    function setTokenRegistry(
        address _tokenRegistry
    ) external onlyOwner {
        Storage storage $ = getStorage();
        if (_tokenRegistry == address(0)) {
            revert InvalidTokenRegistry();
        }
        $.tokenRegistry = _tokenRegistry;
    }

    // Set ChainBalanceManager for a source chain
    function setChainBalanceManager(uint32 chainId, address chainBalanceManager) external onlyOwner {
        Storage storage $ = getStorage();
        $.chainBalanceManagers[chainId] = chainBalanceManager;
        emit ChainBalanceManagerSet(chainId, chainBalanceManager);
    }

    // Cross-chain message handler (receives deposit messages from ChainBalanceManager)
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _messageBody) external payable override {
        Storage storage $ = getStorage();
        if (msg.sender != $.mailbox) {
            revert OnlyMailbox();
        }

        // Verify sender is authorized ChainBalanceManager
        address expectedSender = $.chainBalanceManagers[_origin];
        if (expectedSender == address(0)) {
            revert UnknownOriginChain(_origin);
        }
        bytes32 expectedSenderBytes = bytes32(uint256(uint160(expectedSender)));
        if (_sender != expectedSenderBytes) {
            revert InvalidSender(expectedSenderBytes, _sender);
        }

        // Decode message type
        uint8 messageType = abi.decode(_messageBody, (uint8));

        if (messageType == HyperlaneMessages.DEPOSIT_MESSAGE) {
            _handleDepositMessage(_origin, _messageBody);
        } else {
            revert UnknownMessageType();
        }
    }

    // Handle deposit notification from source chain
    function _handleDepositMessage(uint32 _origin, bytes calldata _messageBody) internal {
        HyperlaneMessages.DepositMessage memory message = abi.decode(_messageBody, (HyperlaneMessages.DepositMessage));

        Storage storage $ = getStorage();

        // Replay protection
        bytes32 messageId = keccak256(abi.encodePacked(_origin, message.user, message.nonce));
        if ($.processedMessages[messageId]) {
            revert MessageAlreadyProcessed(messageId);
        }
        $.processedMessages[messageId] = true;

        // Mint synthetic tokens directly to user
        Currency syntheticCurrency = Currency.wrap(message.syntheticToken);
        uint256 currencyId = syntheticCurrency.toId();

        // Mint actual ERC20 synthetic tokens to BalanceManager (vault)
        ISyntheticERC20 syntheticToken = ISyntheticERC20(message.syntheticToken);
        syntheticToken.mint(address(this), message.amount);

        // Update internal balance tracking for CLOB system
        $.balanceOf[message.user][currencyId] += message.amount;

        emit CrossChainDepositReceived(message.user, syntheticCurrency, message.amount, _origin);
        emit Deposit(message.user, currencyId, message.amount);
    }

    // Request withdrawal to source chain (burns synthetic, sends message)
    function requestWithdraw(
        Currency syntheticCurrency,
        uint256 amount,
        uint32 targetChainId,
        address recipient
    ) external nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();
        address targetChainBM = $.chainBalanceManagers[targetChainId];
        if (targetChainBM == address(0)) {
            revert TargetChainNotSupported(targetChainId);
        }

        // Burn synthetic tokens and update internal balance
        uint256 currencyId = syntheticCurrency.toId();
        if ($.balanceOf[msg.sender][currencyId] < amount) {
            revert InsufficientBalance(msg.sender, currencyId, amount, $.balanceOf[msg.sender][currencyId]);
        }

        // Burn actual ERC20 synthetic tokens from BalanceManager (vault)
        ISyntheticERC20 syntheticToken = ISyntheticERC20(Currency.unwrap(syntheticCurrency));
        syntheticToken.burn(address(this), amount);

        // Update internal balance tracking
        $.balanceOf[msg.sender][currencyId] -= amount;

        // Get user nonce and increment
        uint256 currentNonce = $.userNonces[msg.sender]++;

        // Create withdraw message
        HyperlaneMessages.WithdrawMessage memory message = HyperlaneMessages.WithdrawMessage({
            messageType: HyperlaneMessages.WITHDRAW_MESSAGE,
            syntheticToken: Currency.unwrap(syntheticCurrency),
            recipient: recipient,
            amount: amount,
            targetChainId: targetChainId,
            nonce: currentNonce
        });

        // Send cross-chain message
        bytes memory messageBody = abi.encode(message);
        bytes32 recipientAddress = bytes32(uint256(uint160(targetChainBM)));

        IMailbox($.mailbox).dispatch(targetChainId, recipientAddress, messageBody);

        emit CrossChainWithdrawSent(msg.sender, syntheticCurrency, amount, targetChainId);
        emit Withdrawal(msg.sender, currencyId, amount);
    }

    // View functions for cross-chain
    function getMailboxConfig() external view returns (address mailbox, uint32 localDomain) {
        Storage storage $ = getStorage();
        return ($.mailbox, $.localDomain);
    }

    function getChainBalanceManager(
        uint32 chainId
    ) external view returns (address) {
        return getStorage().chainBalanceManagers[chainId];
    }

    function getUserNonce(
        address user
    ) external view returns (uint256) {
        return getStorage().userNonces[user];
    }

    function isMessageProcessed(
        bytes32 messageId
    ) external view returns (bool) {
        return getStorage().processedMessages[messageId];
    }

    // Deposit local tokens and mint synthetic tokens on the same chain
    function depositLocal(address token, uint256 amount, address recipient) external nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (token == address(0)) {
            revert InvalidTokenAddress();
        }
        if (recipient == address(0)) {
            revert InvalidRecipientAddress();
        }

        Storage storage $ = getStorage();
        
        if ($.tokenRegistry == address(0)) {
            revert TokenRegistryNotSet();
        }

        uint32 currentChain = _getCurrentChainId();

        // Use TokenRegistry to validate local mapping (sourceChain == targetChain)
        if (!TokenRegistry($.tokenRegistry).isTokenMappingActive(currentChain, token, currentChain)) {
            revert TokenNotSupportedForLocalDeposits(token);
        }

        // Get synthetic token address from TokenRegistry
        address syntheticToken = TokenRegistry($.tokenRegistry).getSyntheticToken(currentChain, token, currentChain);

        // Convert amount using TokenRegistry decimal conversion
        uint256 syntheticAmount =
            TokenRegistry($.tokenRegistry).convertAmountForMapping(currentChain, token, currentChain, amount, true);
        
        // Transfer real tokens to this contract (vault them)
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        // Supply to LendingManager for yield generation - MUST succeed
        if ($.lendingManager != address(0)) {
            // Approve lending manager to spend tokens
            IERC20(token).approve($.lendingManager, amount);
            
            // Call LendingManager to deposit under the user's address for yield management
            ILendingManager($.lendingManager).supplyForUser(recipient, token, amount);
        }

        // Mint synthetic tokens to BalanceManager (vault)
        ISyntheticERC20(syntheticToken).mint(address(this), syntheticAmount);

        // Update internal balance tracking for CLOB system
        uint256 currencyId = Currency.wrap(syntheticToken).toId();
        $.balanceOf[recipient][currencyId] += syntheticAmount;
        // Track total internal supply for yield calculations
        $.totalInternalSupply[syntheticToken] += syntheticAmount;

        emit LocalDeposit(recipient, token, syntheticToken, amount, syntheticAmount);
        emit Deposit(recipient, currencyId, syntheticAmount);
    }

    /**
     * @dev Get current chain ID
     */
    function _getCurrentChainId() internal view returns (uint32) {
        return uint32(block.chainid);
    }

    /**
     * @dev Get TokenRegistry address
     */
    function getTokenRegistry() external view returns (address) {
        return getStorage().tokenRegistry;
    }

    /**
     * @dev Get cross-chain configuration
     */
    function getCrossChainConfig() external view returns (address mailbox, uint32 localDomain) {
        Storage storage $ = getStorage();
        return ($.mailbox, $.localDomain);
    }

    // =============================================================
    //                      LENDING FUNCTIONS
    // =============================================================

    /// @notice Borrow tokens on behalf of a user through LendingManager
    /// @param user The user to borrow for
    /// @param token The token to borrow
    /// @param amount The amount to borrow
    function borrowForUser(address user, address token, uint256 amount) external nonReentrant {
        Storage storage $ = getStorage();
        
        if ($.lendingManager == address(0)) revert LendingManagerNotSet();
        
        // Only authorized callers can borrow on behalf of users
        bool isAuthorized = msg.sender == user || $.authorizedOperators[msg.sender];
        require(isAuthorized, "Unauthorized");
        
        try ILendingManager($.lendingManager).borrowForUser(user, token, amount) {
            // Success - borrow completed
        } catch {
            revert BorrowFailed();
        }
    }

    /// @notice Repay tokens on behalf of a user through LendingManager
    /// @param user The user to repay for
    /// @param token The token to repay
    /// @param amount The amount to repay
    function repayForUser(address user, address token, uint256 amount) external nonReentrant {
        Storage storage $ = getStorage();

        if ($.lendingManager == address(0)) revert LendingManagerNotSet();

        // Only authorized callers can repay on behalf of users
        bool isAuthorized = msg.sender == user || $.authorizedOperators[msg.sender];
        require(isAuthorized, "Unauthorized");

        // Transfer tokens from this contract (received from router) to LendingManager
        IERC20(token).transfer($.lendingManager, amount);

        // Now call LendingManager to handle the repayment logic
        try ILendingManager($.lendingManager).repayForUser(user, token, amount) {
            // Success - repayment completed
        } catch {
            revert RepayFailed();
        }
    }

    /// @notice Repay debt using user's synthetic token balance (for auto-repay from OrderBook)
    /// @dev Deducts synthetic balance and reduces debt in LendingManager
    /// @param user The user to repay for
    /// @param syntheticToken The synthetic token to deduct from user's balance
    /// @param underlyingToken The underlying token for debt repayment
    /// @param amount The amount to repay
    function repayFromSyntheticBalance(
        address user,
        address syntheticToken,
        address underlyingToken,
        uint256 amount
    ) external nonReentrant {
        Storage storage $ = getStorage();

        if ($.lendingManager == address(0)) revert LendingManagerNotSet();

        // Only authorized operators (OrderBooks) can call this
        require($.authorizedOperators[msg.sender], "Unauthorized");

        // Verify synthetic token maps to underlying
        require($.syntheticTokens[underlyingToken] == syntheticToken, "Token mismatch");

        // Deduct synthetic token balance from user
        uint256 currencyId = Currency.wrap(syntheticToken).toId();
        require($.balanceOf[user][currencyId] >= amount, "Insufficient balance");
        $.balanceOf[user][currencyId] -= amount;

        // Execute repayment through LendingManager
        // LendingManager already holds the underlying tokens from deposits
        // We just need to reduce the user's debt
        try ILendingManager($.lendingManager).repayFromBalance(user, underlyingToken, amount) {
            emit AutoRepayFromBalance(user, syntheticToken, underlyingToken, amount);
        } catch {
            // Revert the balance deduction if repayment fails
            $.balanceOf[user][currencyId] += amount;
            revert RepayFailed();
        }
    }

    /// @notice Seize collateral from a user during liquidation (reduces gsToken balance)
    /// @param user The user whose collateral is being seized
    /// @param underlyingToken The underlying token address
    /// @param amount The amount of collateral to seize
    function seizeCollateral(
        address user,
        address underlyingToken,
        uint256 amount
    ) external {
        Storage storage $ = getStorage();

        // Only LendingManager can seize collateral
        require(msg.sender == $.lendingManager, "Only LendingManager");

        address syntheticToken = $.syntheticTokens[underlyingToken];
        require(syntheticToken != address(0), "Unknown token");

        uint256 currencyId = Currency.wrap(syntheticToken).toId();
        uint256 userBalance = $.balanceOf[user][currencyId];

        // Seize up to the user's balance
        uint256 seizeAmount = amount > userBalance ? userBalance : amount;
        $.balanceOf[user][currencyId] -= seizeAmount;

        emit CollateralSeized(user, syntheticToken, underlyingToken, seizeAmount);
    }

    event AutoRepayFromBalance(address indexed user, address indexed syntheticToken, address indexed underlyingToken, uint256 amount);
    event CollateralSeized(address indexed user, address indexed syntheticToken, address indexed underlyingToken, uint256 amount);
}
