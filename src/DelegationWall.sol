// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

/// @title DelegationWall - Release 1, Build 1
/// @author Aragon Association - 2024
/// @notice A smart contract where any wallet can register its own libsodium public key for encryption purposes
contract DelegationWall {
    struct Candidate {
        bytes contentUrl;
    }

    /// @dev Stores the data registered by the delegate candidates
    mapping(address => Candidate) public candidates;
    /// @dev Keeps track of the addresses that have been already registered, used to enumerate.
    address[] public candidateAddresses;

    /// @notice Emitted when a wallet registers as a candidate
    event CandidateRegistered(address indexed candidate, bytes contentUrl);

    /// @notice Raised when a delegate registers with an empty contentUrl
    error EmptyContent();

    function register(bytes memory _contentUrl) public {
        if (_contentUrl.length == 0) revert EmptyContent();

        if (candidates[msg.sender].contentUrl.length == 0) {
            candidateAddresses.push(msg.sender);
        }

        candidates[msg.sender].contentUrl = _contentUrl;

        emit CandidateRegistered(msg.sender, _contentUrl);
    }

    function candidateCount() public view returns (uint256) {
        return candidateAddresses.length;
    }
}