// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import {NonblockingLzApp} from "./lzApp/NonblockingLzApp.sol";

/// @title OptimisticTokenVotingPlugin
/// @author Aragon Association - 2023
/// @notice The abstract implementation of optimistic majority plugins.
///
/// @dev This contract implements the `IOptimisticTokenVoting` interface.
contract L2VetoAggregation is NonblockingLzApp {
    struct Proposal {
        uint256 startDate;
        uint64 endDate;
        uint256 vetoes;
        bool bridged;
    }
    /// @notice A mapping for the addresses that have vetoed
    mapping(uint256 => mapping(address => bool)) vetoed;

    /// @notice A container for the majority voting bridge settings that will be required when bridging and receiving the proposals from other chains
    /// @param chainID A parameter to select the id of the destination chain
    /// @param bridge A parameter to select the address of the bridge you want to interact with
    /// @param l2vVotingAggregator A parameter to select the address of the voting contract that will live in the L2
    struct BridgeSettings {
        uint16 chainId;
        address bridge;
        address l1Plugin;
    }

    IVotesUpgradeable immutable votingToken;
    BridgeSettings bridgeSettings;

    /// @notice A mapping for the live proposals
    mapping(uint256 => Proposal) internal liveProposals;

    error ProposalEnded();
    error UserAlreadyVetoed();
    error ProposalAlreadyBridged();
    error BridgeAlreadySet();

    constructor(IVotesUpgradeable _votingToken) {
        votingToken = _votingToken;
    }

    /// @notice A function to initialize the bridge settings
    /// @param _bridgeSettings A parameter to set the bridge settings
    function initialize(BridgeSettings memory _bridgeSettings) public {
        if (bridgeSettings.chainId != 0) {
            revert BridgeAlreadySet();
        }
        bridgeSettings = _bridgeSettings;
        __LzApp_init(bridgeSettings.bridge);

        bytes memory remoteAddresses = abi.encodePacked(
            _bridgeSettings.l1Plugin,
            address(this)
        );
        setTrustedRemote(_bridgeSettings.chainId, remoteAddresses);
    }

    // This function is called when data is received. It overrides the equivalent function in the parent contract.
    // This function should only be called from the L2 to send the aggregated votes and nothing else
    /// @notice A function to receive the data from the L1
    /// @param _srcChainId A parameter to select the id of the source chain
    /// @param _srcAddress A parameter to select the address of the source
    /// @param _nonce A parameter to select the nonce
    /// @param _payload A parameter to select the payload
    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal override {
        // The LayerZero _payload (message) is decoded as a string and stored in the "data" variable.
        require(
            _msgSender() == address(this),
            "NonblockingLzApp: caller must be LzApp"
        );
        (uint256 proposalId, uint256 startDate, uint64 endDate) = abi.decode(
            _payload,
            (uint256, uint256, uint64)
        );

        liveProposals[proposalId] = Proposal(startDate, endDate, 0, false);
    }

    /// @notice A function to create a new proposal
    /// @param _proposalId The id of the proposal to be vetoed
    function veto(uint256 _proposalId) external {
        address _voter = _msgSender();

        Proposal storage proposal_ = liveProposals[_proposalId];
        if (proposal_.endDate < block.timestamp) {
            revert ProposalEnded();
        }

        if (vetoed[_proposalId][_voter] == true) {
            revert UserAlreadyVetoed();
        }

        vetoed[_proposalId][_voter] = true;

        uint256 votingPower = votingToken.getPastVotes(
            _voter,
            proposal_.startDate
        );

        proposal_.vetoes += votingPower;
    }

    /// @notice A function to bridge the results of a proposal
    /// @param _proposalId The id of the proposal to be bridged
    function bridgeResults(uint256 _proposalId) external payable {
        // TODO: We should allow the bridging of the results to be open any time
        Proposal storage proposal_ = liveProposals[_proposalId];
        if (proposal_.bridged) {
            revert ProposalAlreadyBridged();
        }
        bytes memory encodedMessage = abi.encode(_proposalId, proposal_.vetoes);

        proposal_.bridged = true;

        _lzSend({
            _dstChainId: bridgeSettings.chainId,
            _payload: encodedMessage,
            _refundAddress: payable(msg.sender),
            _zroPaymentAddress: address(0),
            _adapterParams: bytes(""),
            _nativeFee: address(this).balance
        });
    }

    /// @notice A function to get the proposal
    /// @param _proposal The id of the proposal to be fetched
    /// @return Proposal The proposal
    function getProposal(
        uint256 _proposal
    ) external view returns (Proposal memory) {
        return liveProposals[_proposal];
    }

    /// @notice A function to get the voting token
    /// @return IVotesUpgradeable The voting token
    function getVotingToken() public view returns (IVotesUpgradeable) {
        return votingToken;
    }
}