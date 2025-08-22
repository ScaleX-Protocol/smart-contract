// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;
import {IMessageRecipient} from "./interfaces/IMessageRecipient.sol";
import {ISyntheticERC20} from "./interfaces/ISyntheticERC20.sol";
import {IBalanceManager} from "../core/interfaces/IBalanceManager.sol";
import {Currency} from "./libraries/Currency.sol";

contract BridgeSyntheticTokenReceiver is IMessageRecipient  {
    address public balanceManager;
    address public mailboxAddress;

    constructor(address _balanceManager, address _mailboxAddress) {
        balanceManager = _balanceManager;
        mailboxAddress = _mailboxAddress;
    }

    event ReceivedMessage(
        uint32 indexed origin,
        bytes32 indexed sender,
        string message
    );

    modifier onlyMailbox() {
        require(
            msg.sender == mailboxAddress,
            "MailboxClient: sender not mailbox"
        );
        _;
    }

    function handle(
        uint32 origin,
        bytes32 sender,
        bytes calldata message
    ) external override onlyMailbox payable {
        (address token, address to, uint256 amount) = abi.decode(message, (address, address, uint256));

        ISyntheticERC20(token).mint(to, amount);

        IBalanceManager(balanceManager).deposit(
            Currency.wrap(token),
            amount,
            to,
            to
        );

        emit ReceivedMessage(origin, sender, "Minted tokens and deposited");
    }
}