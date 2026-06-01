// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Bordeaux
/// @notice Voyager ledger — codename "velvet atlas crawl"
/// @dev Destination reviews, scrape attestations, and AI insight lanes; pull-only tips.

library BrdxMath {
    error BRX_MathFault();
    uint256 internal constant RATIO_BASE = 10_000;
    function clampU8(uint256 v, uint8 lo, uint8 hi) internal pure returns (uint8) {
        if (v < lo) return lo;
        if (v > hi) return hi;
        return uint8(v);
    }
    function mulBps(uint256 amt, uint256 bps) internal pure returns (uint256) {
        unchecked { return (amt * bps) / RATIO_BASE; }
    }
    function saturatingAdd(uint256 a, uint256 b, uint256 cap) internal pure returns (uint256) {
        unchecked {
            uint256 s = a + b;
            if (s < a || s > cap) revert BRX_MathFault();
            return s;
        }
    }
}

contract Bordeaux {
    // ── faults ───────────────────────────────────────────────────────────
    error BRX_NotCurator();
    error BRX_LanePaused();
    error BRX_ZeroAddr();
    error BRX_ZeroAmt();
    error BRX_Reentered();
    error BRX_DestMissing();
    error BRX_DestRetired();
    error BRX_ReviewExists();
    error BRX_ReviewMissing();
    error BRX_StarOutOfRange();
    error BRX_CapHit();
    error BRX_BadEpoch();
    error BRX_ScrapeOpen();
    error BRX_ScrapeMissing();
    error BRX_ScrapeClosed();
    error BRX_InsightStale();
    error BRX_ConfLow();
    error BRX_ConfHigh();
    error BRX_HandoffPending();
    error BRX_NoHandoff();
    error BRX_BadHandoff();
    error BRX_DigestVoid();
    error BRX_AlreadyVoted();
    error BRX_SelfVote();
    error BRX_TipTooSmall();
    error BRX_TransferFail();
    error BRX_BatchTooWide();
    error BRX_ArrayMismatch();
    error BRX_LaneFault_28();
    error BRX_LaneFault_29();
    error BRX_LaneFault_30();
    error BRX_LaneFault_31();
    error BRX_LaneFault_32();
    error BRX_LaneFault_33();
    error BRX_LaneFault_34();
    error BRX_LaneFault_35();
    error BRX_LaneFault_36();

    event Posted(bytes32 indexed reviewId, uint256 indexed destId, address indexed author, uint8 stars);
    event Voted(bytes32 indexed reviewId, address indexed voter, bool up);
    event Tipped(bytes32 indexed reviewId, address indexed from, uint256 weiAmt);
    event Scraped(bytes32 indexed jobId, uint256 indexed destId, bytes32 urlHash);
    event Sealed(bytes32 indexed jobId, bytes32 payloadHash, uint16 confidence);
    event Inferred(bytes32 indexed insightId, uint256 indexed destId, uint16 modelConf);
    event Opened(uint256 indexed destId, bytes32 placeTag, uint8 tier);
    event Shifted(uint256 indexed epochId, uint64 wallTs, uint256 reviewWeight);
    event Paused(bool lanePaused, address indexed by);
    event Nominated(address indexed prev, address indexed pending);
    event Swapped(address indexed prev, address indexed next);
    event Ping_0(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Ping_1(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Ping_2(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Ping_3(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Ping_4(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Ping_5(uint256 indexed lineId, address indexed actor, uint256 meta);
