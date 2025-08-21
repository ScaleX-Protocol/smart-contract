// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;
import {IMessageRecipient} from "./interfaces/IMessageRecipient.sol";
import {ISyntheticERC20} from "./interfaces/ISyntheticERC20.sol";
import {IMailbox} from "./interfaces/IMailbox.sol";
import {IBalanceManager} from "../core/interfaces/IBalanceManager.sol";
import { TypeCasts } from "./libraries/TypeCasts.sol";

contract BridgeSyntheticTokenSender {
    address public balanceManager;
    address public mailboxAddress;

    event WithdrawalRequested(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint32 destinationDomain,
        address destinationRecipient,
        bytes32 messageId
    );

    constructor(address _balanceManager, address _mailboxAddress) {
        balanceManager = _balanceManager;
        mailboxAddress = _mailboxAddress;
    }

    function withdraw(
        uint32 destinationChainId,
        address appDestinationAddress,
        address user,
        address token,
        uint256 amount
    ) external payable returns (bytes32) {
        IBalanceManager(balanceManager).withdraw(
            Currency.wrap(token),
            amount,
            user
        );
        ISyntheticERC20(token).burn(msg.sender, amount);

        bytes memory messageBody = abi.encode(token, user, amount);
        bytes32 recipientBytes32 = TypeCasts.addressToBytes32(appDestinationAddress);

        uint256 fee = IMailbox(mailboxAddress).quoteDispatch(destinationChainId, recipientBytes32, messageBody);
        require(msg.value >= fee, "Insufficient fee for dispatch");

        bytes32 messageId = IMailbox(mailboxAddress).dispatch{value: fee}(
            destinationChainId,
            recipientBytes32,
            messageBody
        );


        emit WithdrawalRequested(msg.sender, token, amount, destinationChainId, user, messageId);
        return messageId;
    }
}