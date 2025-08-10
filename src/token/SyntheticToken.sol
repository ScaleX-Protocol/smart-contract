// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ISyntheticERC20} from "@gtxcore/interfaces/ISyntheticERC20.sol";

contract SyntheticToken is ERC20, ISyntheticERC20 {
    address public bridgeSyntheticTokenReceiver;

    modifier onlyBridgeSyntheticTokenReceiver() {
        require(msg.sender == bridgeSyntheticTokenReceiver, "Not authorized");
        _;
    }

    constructor(string memory name_, string memory symbol_, address _bridgeSyntheticTokenReceiver) ERC20(name_, symbol_) {
        bridgeSyntheticTokenReceiver = _bridgeSyntheticTokenReceiver;
    }

    function mint(address to, uint256 amount) external onlyBridgeSyntheticTokenReceiver {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyBridgeSyntheticTokenReceiver {
        _burn(from, amount);
    }
}
