// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMessageTransmitterV2 {
    function receiveMessage(
        bytes calldata message,
        bytes calldata attestation
    ) external returns (bool);
}