//SPDX-Licence-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);

    error Vault__RedeemFailed();

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }
    /**
     * @notice Fallback function to accept ETH deposits
     * @dev This function allows the contract to accept ETH deposits directly
     */
    receive() external payable {}

    /**
     * @notice Deposit ETH into the vault and receive rebase tokens
     * @dev This function mints rebase tokens to the sender based on the amount of ETH deposited
     * emits a Deposit event
     */
    function deposit() external payable {
        i_rebaseToken.mint(msg.sender, msg.value, i_rebaseToken.getInterestRate());
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Redeem rebase tokens for ETH from the vault
     * @dev This function burns rebase tokens from the sender and sends ETH back to them
     * @param _amount The amount of rebase tokens to redeem
     * emits a Redeem event
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        i_rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
    }

    /**
     * @notice Get the address of the rebase token contract
     * @return The address of the rebase token contract
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
