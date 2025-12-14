// SDPX-Licence-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
* @title RebaseToken
* @author RomThpt
* @notice A cross-chain rebase token that incentivises users to depostit into a vault and gain interest in rewards
* @notice The interest rate in the smart contract can only decrease
* @notice Each user will have their own interest rate taht is the global interest rate at the time of their deposit
*/
contract RebaseToken is ERC20, Ownable {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 newInterestRate, uint256 currentInterestRate);

    uint256 private s_interestRate = 5e10;
    mapping(address => uint256) private s_userInterestRates;

    event InterestRateUpdated(uint256 newInterestRate);

    constructor(uint256 _initialInterestRate) ERC20("RebaseToken", "RBT") {}

    /*
    * @notice Set the interest rate in the contract
    * @param _newInterestRate The new interest rate to be set
    * @dev The new interest rate can only be lower than the current interest rate
    */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // Implementation for setting a new interest rate
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(_newInterestRate, s_interestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateUpdated(_newInterestRate);
    }

    /*
    * @notice Mint rebase tokens to a user
    * @dev Internal function to mint tokens
    * @param _to The address to mint tokens to
    * @param _amount The amount of tokens to mint
    */
    function mint(address _to, uint256 _amount) external {
        s_userInterestRates[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /*
    * @notice Burn rebase tokens from a user
    * @dev Internal function to burn tokens
    * @param _from The address to burn tokens from
    * @param _amount The amount of tokens to burn
    */
    function burn(address _from, uint256 _amount) external {}

    /*****GETTERS******/

    /*
    * @notice Get the current global interest rate
    * @return The current global interest rate
    */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRates[_user];
    }
}
