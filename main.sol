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
    event Ping_6(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Ping_7(uint256 indexed lineId, address indexed actor, uint256 meta);
    event Ping_8(uint256 indexed lineId, address indexed actor, uint256 meta);

    enum BrdxDestPhase { Draft, Live, Archived }
    enum BrdxScrapePhase { Queued, Running, Done, Failed }

    struct BrdxDestination {
        BrdxDestPhase phase;
        uint8 tierBand;
        uint64 openedAt;
        uint32 reviewCount;
        uint32 scrapeCount;
        uint256 reputationSum;
        bytes32 placeTag;
    }

    struct BrdxReview {
        uint256 destId;
        address author;
        bytes32 bodyHash;
        uint8 stars;
        uint32 upVotes;
        uint32 downVotes;
        uint256 tipsWei;
        uint64 postedAt;
        bool exists;
    }

    struct BrdxScrapeJob {
        uint256 destId;
        address requester;
        bytes32 urlHash;
        BrdxScrapePhase phase;
        bytes32 resultHash;
        uint16 confidence;
        uint64 queuedAt;
    }

    struct BrdxInsightCell {
        uint256 destId;
        bytes32 modelTag;
        bytes32 summaryHash;
        uint16 confidence;
        uint64 stampedAt;
    }

    struct BrdxEpochRail {
        uint64 startedAt;
        uint256 reviewWeight;
        uint256 scrapeWeight;
        bytes32 mixHA;
        bytes32 mixHB;
    }

    uint256 public constant BRDX_STAR_MAX = 8;
    uint256 public constant BRDX_REVIEW_FEE = 0.003 ether;
    uint256 public constant BRDX_SCRAPE_FEE = 0.003 ether;
    uint256 public constant BRDX_MAX_REVIEWS = 120;
    uint256 public constant BRDX_SCRAPE_OPEN_CAP = 67;
    uint256 public constant BRDX_CONF_FLOOR = 403;
    uint256 public constant BRDX_CONF_CEIL = 9066;
    uint256 public constant BRDX_EPOCH_BLOCKS = 544;
    uint256 public constant BRDX_REP_CAP = 13543;

    bytes32 private constant _MIX_0 = 0x75919a55fe8f548f53b2503c4c700ba12213deb0c3549528d4474f5ac199c1d4;
    bytes32 private constant _MIX_1 = 0xdbba9d86e72c3c4522dca7e9c008a46bf851c859f8fa3a48867f12921d6b5ea9;
    bytes32 private constant _MIX_2 = 0xd5a7abe55fcdbf13f6102dc690de5b7865ace4678ca26fc0eb7d7c82c0d938cc;
    bytes32 private constant _MIX_3 = 0xa80fa76e45e3cdc6c58b0c14ee6b3520a922fbedf5b0f5ee25a478102072c7d9;
    bytes32 private constant _MIX_4 = 0xa33cb156510ec1ee095c44c6cc250805301b5ca372a3dfe7b747251fa966b2d1;
    bytes32 private constant _MIX_5 = 0x358df167d58b1b987967b344e3e4b85a02feb445203543212fe4857e1d07de8b;
    bytes32 private constant _MIX_6 = 0x32877145e65bd7fc4e0b0a893f01c81c221f5fe840471eb2d5b50ec43b3ae3d7;
    bytes32 private constant BRDX_DOMAIN = keccak256("Bordeaux.velvetAtlasCrawl");

    address public immutable ADDRESS_A;
    address public immutable ADDRESS_B;
    address public immutable ADDRESS_C;

    address public curator;
    address public pendingCurator;
    bool public lanePaused;
    uint256 public activeEpoch;
    uint256 public lineSerial;
    uint256 public openScrapeJobs;
