// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ReentrancyErrors} from "seaport-types/src/interfaces/ReentrancyErrors.sol";

import {LowLevelHelpers} from "./LowLevelHelpers.sol";

import {_revertInvalidMsgValue, _revertNoReentrantCalls} from "seaport-types/src/lib/ConsiderationErrors.sol";

import {
    _ENTERED_AND_ACCEPTING_NATIVE_TOKENS, _ENTERED, _NOT_ENTERED
} from "seaport-types/src/lib/ConsiderationConstants.sol";

/**
 * @title ReentrancyGuard
 * @author 0age
 * @notice ReentrancyGuard contains a storage variable and related functionality
 *         for protecting against reentrancy.
 */
contract ReentrancyGuard is ReentrancyErrors, LowLevelHelpers {
    // Prevent reentrant calls on protected functions.
    uint256 private _reentrancyGuard;

    /**
     * @dev Internal function to ensure that a sentinel value for the reentrancy
     *      guard is not currently set and, if not, to set a sentinel value for
     *      the reentrancy guard based on whether or not native tokens may be
     *      received during execution or not.
     *
     * @param acceptNativeTokens A boolean indicating whether native tokens may
     *                           be received during execution or not.
     */
    function _setReentrancyGuard(bool acceptNativeTokens) internal {
        // Ensure that the reentrancy guard is not already set.
        _assertNonReentrant();

        // Set the reentrancy guard. A value of 2 indicates that native tokens
        // may not be accepted during execution, whereas a value of 3 indicates
        // that they will be accepted (with any remaining native tokens returned
        // to the caller).
            assembly {
                tstore(
                    _reentrancyGuard.slot,
                    add(
                        _ENTERED,
                        acceptNativeTokens
                    )
                )
            }
    }

    /**
     * @dev Internal function to unset the reentrancy guard sentinel value.
     */
    function _clearReentrancyGuard() internal {
        // Clear the reentrancy guard.
       assembly {
            tstore(
                _reentrancyGuard.slot,
                _NOT_ENTERED
            )
       }
    }

    /**
     * @dev Internal view function to ensure that a sentinel value for the
     *         reentrancy guard is not currently set.
     */
    function _assertNonReentrant() internal view {
        // Ensure that the reentrancy guard is not currently set.
        if (_tloadReentrancyGuard() != _NOT_ENTERED) {
            _revertNoReentrantCalls();
        }
    }

    /**
     * @dev Internal view function to ensure that the sentinel value indicating
     *      native tokens may be received during execution is currently set.
     */
    function _assertAcceptingNativeTokens() internal view {
        // Ensure that the reentrancy guard is not currently set.
        if (_tloadReentrancyGuard() != _ENTERED_AND_ACCEPTING_NATIVE_TOKENS) {
            _revertInvalidMsgValue(msg.value);
        }
    }

    function _tloadReentrancyGuard() internal view returns (uint256 reentrancyGuard) {
        assembly {
            let reentrancyGuardSlot := _reentrancyGuard.slot
            reentrancyGuard := tload(reentrancyGuardSlot)
        }
    }
}
