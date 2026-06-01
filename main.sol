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
    uint256 public totalTipsWei;
    uint256 public genesisBlock;

    mapping(uint256 => BrdxDestination) public destinations;
    mapping(bytes32 => BrdxReview) public reviews;
    mapping(bytes32 => BrdxScrapeJob) public scrapeJobs;
    mapping(bytes32 => BrdxInsightCell) public insights;
    mapping(uint256 => BrdxEpochRail) public epochRails;
    mapping(uint256 => mapping(address => uint256)) public reviewerRep;
    mapping(bytes32 => mapping(address => bool)) public voteCast;
    mapping(bytes32 => bool) public reviewIdUsed;
    mapping(bytes32 => bool) public scrapeIdUsed;
    mapping(bytes32 => bool) public insightIdUsed;
    mapping(address => bytes32[]) private _reviewsByAuthor;
    uint256 private _guard;

    modifier nonReentrant() {
        if (_guard == 2) revert BRX_Reentered();
        _guard = 2;
        _;
        _guard = 1;
    }

    modifier onlyCurator() {
        if (msg.sender != curator) revert BRX_NotCurator();
        _;
    }

    modifier whenLaneLive() {
        if (lanePaused) revert BRX_LanePaused();
        _;
    }

    constructor(address curator_) {
        if (curator_ == address(0)) revert BRX_ZeroAddr();
        ADDRESS_A = 0x4fE0796a76b797746f0D84e8c41C76364248a79b;
        ADDRESS_B = 0xBc45912d32d3C004a2f8af7Ca7146F67b4524c33;
        ADDRESS_C = 0xA00c6a6235dA5Ceb2Da44153799ca7B0128Ec2B9;
        curator = curator_;
        _guard = 1;
        genesisBlock = block.number;
        activeEpoch = 1;
        _primeEpoch(1);
        _seedDestinations();
    }

    function nominateCurator(address next_) external onlyCurator {
        if (next_ == address(0)) revert BRX_BadHandoff();
        pendingCurator = next_;
        emit Nominated(curator, next_);
    }

    function acceptCuratorRole() external {
        if (msg.sender != pendingCurator) revert BRX_NoHandoff();
        address prev = curator;
        curator = pendingCurator;
        pendingCurator = address(0);
        emit Swapped(prev, curator);
    }

    function setLanePaused(bool v) external onlyCurator {
        lanePaused = v;
        emit Paused(v, msg.sender);
    }

    function advanceEpoch() external onlyCurator whenLaneLive {
        uint256 n = activeEpoch + 1;
        if (n > 38) revert BRX_BadEpoch();
        activeEpoch = n;
        _primeEpoch(n);
        emit Shifted(n, uint64(block.timestamp), _epochReviewWeight());
    }

    function retireDestination(uint256 destId) external onlyCurator {
        BrdxDestination storage d = destinations[destId];
        if (d.phase == BrdxDestPhase.Draft) revert BRX_DestMissing();
        d.phase = BrdxDestPhase.Archived;
    }

    function postReview(
        bytes32 reviewId,
        uint256 destId,
        bytes32 bodyHash,
        uint8 stars
    ) external payable nonReentrant whenLaneLive {
        if (reviewId == bytes32(0)) revert BRX_DigestVoid();
        if (reviewIdUsed[reviewId]) revert BRX_ReviewExists();
        if (msg.value < BRDX_REVIEW_FEE) revert BRX_TipTooSmall();
        if (stars == 0 || stars > BRDX_STAR_MAX) revert BRX_StarOutOfRange();
        BrdxDestination storage d = destinations[destId];
        if (d.phase != BrdxDestPhase.Live) revert BRX_DestRetired();
        if (d.reviewCount >= BRDX_MAX_REVIEWS) revert BRX_CapHit();
        reviewIdUsed[reviewId] = true;
        reviews[reviewId] = BrdxReview({
            destId: destId,
            author: msg.sender,
            bodyHash: bodyHash,
            stars: stars,
            upVotes: 0,
            downVotes: 0,
            tipsWei: msg.value,
            postedAt: uint64(block.timestamp),
            exists: true
        });
        unchecked {
            d.reviewCount += 1;
            d.reputationSum = BrdxMath.saturatingAdd(d.reputationSum, uint256(stars) * 100, BRDX_REP_CAP);
        }
        reviewerRep[activeEpoch][msg.sender] += uint256(stars) * 10;
        totalTipsWei += msg.value;
        _reviewsByAuthor[msg.sender].push(reviewId);
        emit Posted(reviewId, destId, msg.sender, stars);
    }

    function castVote(bytes32 reviewId, bool up) external whenLaneLive {
        BrdxReview storage r = reviews[reviewId];
        if (!r.exists) revert BRX_ReviewMissing();
        if (r.author == msg.sender) revert BRX_SelfVote();
        if (voteCast[reviewId][msg.sender]) revert BRX_AlreadyVoted();
        voteCast[reviewId][msg.sender] = true;
        if (up) unchecked { r.upVotes += 1; }
        else unchecked { r.downVotes += 1; }
        emit Voted(reviewId, msg.sender, up);
    }

    function tipReview(bytes32 reviewId) external payable nonReentrant whenLaneLive {
        if (msg.value == 0) revert BRX_ZeroAmt();
        BrdxReview storage r = reviews[reviewId];
        if (!r.exists) revert BRX_ReviewMissing();
        r.tipsWei += msg.value;
        totalTipsWei += msg.value;
        _sendNative(r.author, msg.value);
        emit Tipped(reviewId, msg.sender, msg.value);
    }

    function queueScrape(bytes32 jobId, uint256 destId, bytes32 urlHash)
        external
        payable
        nonReentrant
        whenLaneLive
    {
        if (jobId == bytes32(0)) revert BRX_DigestVoid();
        if (scrapeIdUsed[jobId]) revert BRX_ScrapeOpen();
        if (msg.value < BRDX_SCRAPE_FEE) revert BRX_TipTooSmall();
        if (openScrapeJobs >= BRDX_SCRAPE_OPEN_CAP) revert BRX_CapHit();
        BrdxDestination storage d = destinations[destId];
        if (d.phase != BrdxDestPhase.Live) revert BRX_DestRetired();
        scrapeIdUsed[jobId] = true;
        scrapeJobs[jobId] = BrdxScrapeJob({
            destId: destId,
            requester: msg.sender,
            urlHash: urlHash,
            phase: BrdxScrapePhase.Queued,
            resultHash: bytes32(0),
            confidence: 0,
            queuedAt: uint64(block.timestamp)
        });
        unchecked {
            openScrapeJobs += 1;
            d.scrapeCount += 1;
        }
        emit Scraped(jobId, destId, urlHash);
    }

    function sealScrape(bytes32 jobId, bytes32 payloadHash, uint16 confidence) external onlyCurator {
        BrdxScrapeJob storage j = scrapeJobs[jobId];
        if (j.phase != BrdxScrapePhase.Queued && j.phase != BrdxScrapePhase.Running) revert BRX_ScrapeClosed();
        if (confidence < BRDX_CONF_FLOOR) revert BRX_ConfLow();
        if (confidence > BRDX_CONF_CEIL) revert BRX_ConfHigh();
        j.phase = BrdxScrapePhase.Done;
        j.resultHash = payloadHash;
        j.confidence = confidence;
        if (openScrapeJobs > 0) unchecked { openScrapeJobs -= 1; }
        emit Sealed(jobId, payloadHash, confidence);
    }

    function publishInsight(
        bytes32 insightId,
        uint256 destId,
        bytes32 modelTag,
        bytes32 summaryHash,
        uint16 confidence
    ) external onlyCurator whenLaneLive {
        if (insightIdUsed[insightId]) revert BRX_InsightStale();
        if (confidence < BRDX_CONF_FLOOR) revert BRX_ConfLow();
        if (confidence > BRDX_CONF_CEIL) revert BRX_ConfHigh();
        BrdxDestination storage d = destinations[destId];
        if (d.phase != BrdxDestPhase.Live) revert BRX_DestRetired();
        insightIdUsed[insightId] = true;
        insights[insightId] = BrdxInsightCell({
            destId: destId,
            modelTag: modelTag,
            summaryHash: summaryHash,
            confidence: confidence,
            stampedAt: uint64(block.timestamp)
        });
        emit Inferred(insightId, destId, confidence);
    }

    function fundInsightPool() external payable whenLaneLive {
        if (msg.value == 0) revert BRX_ZeroAmt();
        emit Ping_0(lineSerial, msg.sender, msg.value);
        unchecked { lineSerial += 1; }
    }

    function _sendNative(address to, uint256 amt) internal {
        (bool ok, ) = to.call{value: amt}("");
        if (!ok) revert BRX_TransferFail();
    }

    function _primeEpoch(uint256 epochId) internal {
        BrdxEpochRail storage e = epochRails[epochId];
        e.startedAt = uint64(block.timestamp);
        e.reviewWeight = _epochReviewWeight();
        e.scrapeWeight = openScrapeJobs;
        (e.mixHA, e.mixHB) = _splitMix(epochId, e.reviewWeight, e.scrapeWeight);
    }

    function _splitMix(uint256 epochId, uint256 rw, uint256 sw)
        internal
        view
        returns (bytes32 hA, bytes32 hB)
    {
        hA = keccak256(abi.encode(BRDX_DOMAIN, epochId, rw, ADDRESS_A, _MIX_0));
        hB = keccak256(abi.encode(sw, epochId, ADDRESS_B, _MIX_1, BRDX_EPOCH_BLOCKS));
    }

    function reviewDigest(bytes32 reviewId) public view returns (bytes32) {
        BrdxReview storage r = reviews[reviewId];
        (bytes32 hA, bytes32 hB) = _splitMix(r.destId, uint256(uint160(r.author)), r.tipsWei);
        return keccak256(abi.encodePacked(hA, hB, r.bodyHash, ADDRESS_C, _MIX_2));
    }

    function _epochReviewWeight() internal view returns (uint256 w) {
        for (uint256 i = 1; i <= 26; ++i) {
            w += destinations[i].reputationSum;
        }
    }

    function _seedDestinations() internal {
        destinations[1] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(1),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 20,
            placeTag: 0xdbba9d86e72c3c4522dca7e9c008a46bf851c859f8fa3a48867f12921d6b5ea9
        });
        emit Opened(1, 0xdbba9d86e72c3c4522dca7e9c008a46bf851c859f8fa3a48867f12921d6b5ea9, uint8(1));
        destinations[2] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(2),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 37,
            placeTag: 0xd5a7abe55fcdbf13f6102dc690de5b7865ace4678ca26fc0eb7d7c82c0d938cc
        });
        emit Opened(2, 0xd5a7abe55fcdbf13f6102dc690de5b7865ace4678ca26fc0eb7d7c82c0d938cc, uint8(2));
        destinations[3] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(3),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 54,
            placeTag: 0xa80fa76e45e3cdc6c58b0c14ee6b3520a922fbedf5b0f5ee25a478102072c7d9
        });
        emit Opened(3, 0xa80fa76e45e3cdc6c58b0c14ee6b3520a922fbedf5b0f5ee25a478102072c7d9, uint8(3));
        destinations[4] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(4),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 71,
            placeTag: 0xa33cb156510ec1ee095c44c6cc250805301b5ca372a3dfe7b747251fa966b2d1
        });
        emit Opened(4, 0xa33cb156510ec1ee095c44c6cc250805301b5ca372a3dfe7b747251fa966b2d1, uint8(4));
        destinations[5] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(5),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 88,
            placeTag: 0x358df167d58b1b987967b344e3e4b85a02feb445203543212fe4857e1d07de8b
        });
        emit Opened(5, 0x358df167d58b1b987967b344e3e4b85a02feb445203543212fe4857e1d07de8b, uint8(5));
        destinations[6] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(2),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 105,
            placeTag: 0x32877145e65bd7fc4e0b0a893f01c81c221f5fe840471eb2d5b50ec43b3ae3d7
        });
        emit Opened(6, 0x32877145e65bd7fc4e0b0a893f01c81c221f5fe840471eb2d5b50ec43b3ae3d7, uint8(2));
        destinations[7] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(3),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 122,
            placeTag: 0x75919a55fe8f548f53b2503c4c700ba12213deb0c3549528d4474f5ac199c1d4
        });
        emit Opened(7, 0x75919a55fe8f548f53b2503c4c700ba12213deb0c3549528d4474f5ac199c1d4, uint8(3));
        destinations[8] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(4),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 139,
            placeTag: 0xdbba9d86e72c3c4522dca7e9c008a46bf851c859f8fa3a48867f12921d6b5ea9
        });
        emit Opened(8, 0xdbba9d86e72c3c4522dca7e9c008a46bf851c859f8fa3a48867f12921d6b5ea9, uint8(4));
        destinations[9] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(1),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 156,
            placeTag: 0xd5a7abe55fcdbf13f6102dc690de5b7865ace4678ca26fc0eb7d7c82c0d938cc
        });
        emit Opened(9, 0xd5a7abe55fcdbf13f6102dc690de5b7865ace4678ca26fc0eb7d7c82c0d938cc, uint8(1));
        destinations[10] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(2),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 173,
            placeTag: 0xa80fa76e45e3cdc6c58b0c14ee6b3520a922fbedf5b0f5ee25a478102072c7d9
        });
        emit Opened(10, 0xa80fa76e45e3cdc6c58b0c14ee6b3520a922fbedf5b0f5ee25a478102072c7d9, uint8(2));
        destinations[11] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(3),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 190,
            placeTag: 0xa33cb156510ec1ee095c44c6cc250805301b5ca372a3dfe7b747251fa966b2d1
        });
        emit Opened(11, 0xa33cb156510ec1ee095c44c6cc250805301b5ca372a3dfe7b747251fa966b2d1, uint8(3));
        destinations[12] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(4),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 207,
            placeTag: 0x358df167d58b1b987967b344e3e4b85a02feb445203543212fe4857e1d07de8b
        });
        emit Opened(12, 0x358df167d58b1b987967b344e3e4b85a02feb445203543212fe4857e1d07de8b, uint8(4));
        destinations[13] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(5),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 224,
            placeTag: 0x32877145e65bd7fc4e0b0a893f01c81c221f5fe840471eb2d5b50ec43b3ae3d7
        });
        emit Opened(13, 0x32877145e65bd7fc4e0b0a893f01c81c221f5fe840471eb2d5b50ec43b3ae3d7, uint8(5));
        destinations[14] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(2),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 241,
            placeTag: 0x75919a55fe8f548f53b2503c4c700ba12213deb0c3549528d4474f5ac199c1d4
        });
        emit Opened(14, 0x75919a55fe8f548f53b2503c4c700ba12213deb0c3549528d4474f5ac199c1d4, uint8(2));
        destinations[15] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(3),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 258,
            placeTag: 0xdbba9d86e72c3c4522dca7e9c008a46bf851c859f8fa3a48867f12921d6b5ea9
        });
        emit Opened(15, 0xdbba9d86e72c3c4522dca7e9c008a46bf851c859f8fa3a48867f12921d6b5ea9, uint8(3));
        destinations[16] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(4),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 275,
            placeTag: 0xd5a7abe55fcdbf13f6102dc690de5b7865ace4678ca26fc0eb7d7c82c0d938cc
        });
        emit Opened(16, 0xd5a7abe55fcdbf13f6102dc690de5b7865ace4678ca26fc0eb7d7c82c0d938cc, uint8(4));
        destinations[17] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(1),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 292,
            placeTag: 0xa80fa76e45e3cdc6c58b0c14ee6b3520a922fbedf5b0f5ee25a478102072c7d9
        });
        emit Opened(17, 0xa80fa76e45e3cdc6c58b0c14ee6b3520a922fbedf5b0f5ee25a478102072c7d9, uint8(1));
        destinations[18] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(2),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 309,
            placeTag: 0xa33cb156510ec1ee095c44c6cc250805301b5ca372a3dfe7b747251fa966b2d1
        });
        emit Opened(18, 0xa33cb156510ec1ee095c44c6cc250805301b5ca372a3dfe7b747251fa966b2d1, uint8(2));
        destinations[19] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(3),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 326,
            placeTag: 0x358df167d58b1b987967b344e3e4b85a02feb445203543212fe4857e1d07de8b
        });
        emit Opened(19, 0x358df167d58b1b987967b344e3e4b85a02feb445203543212fe4857e1d07de8b, uint8(3));
        destinations[20] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(4),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 343,
            placeTag: 0x32877145e65bd7fc4e0b0a893f01c81c221f5fe840471eb2d5b50ec43b3ae3d7
        });
        emit Opened(20, 0x32877145e65bd7fc4e0b0a893f01c81c221f5fe840471eb2d5b50ec43b3ae3d7, uint8(4));
        destinations[21] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(5),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 360,
            placeTag: 0x75919a55fe8f548f53b2503c4c700ba12213deb0c3549528d4474f5ac199c1d4
        });
        emit Opened(21, 0x75919a55fe8f548f53b2503c4c700ba12213deb0c3549528d4474f5ac199c1d4, uint8(5));
        destinations[22] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(2),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 377,
            placeTag: 0xdbba9d86e72c3c4522dca7e9c008a46bf851c859f8fa3a48867f12921d6b5ea9
        });
        emit Opened(22, 0xdbba9d86e72c3c4522dca7e9c008a46bf851c859f8fa3a48867f12921d6b5ea9, uint8(2));
        destinations[23] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(3),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 394,
            placeTag: 0xd5a7abe55fcdbf13f6102dc690de5b7865ace4678ca26fc0eb7d7c82c0d938cc
        });
        emit Opened(23, 0xd5a7abe55fcdbf13f6102dc690de5b7865ace4678ca26fc0eb7d7c82c0d938cc, uint8(3));
        destinations[24] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(4),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 411,
            placeTag: 0xa80fa76e45e3cdc6c58b0c14ee6b3520a922fbedf5b0f5ee25a478102072c7d9
        });
        emit Opened(24, 0xa80fa76e45e3cdc6c58b0c14ee6b3520a922fbedf5b0f5ee25a478102072c7d9, uint8(4));
        destinations[25] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(1),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 428,
            placeTag: 0xa33cb156510ec1ee095c44c6cc250805301b5ca372a3dfe7b747251fa966b2d1
        });
        emit Opened(25, 0xa33cb156510ec1ee095c44c6cc250805301b5ca372a3dfe7b747251fa966b2d1, uint8(1));
        destinations[26] = BrdxDestination({
            phase: BrdxDestPhase.Live,
            tierBand: uint8(2),
            openedAt: uint64(block.timestamp),
            reviewCount: 0,
            scrapeCount: 0,
            reputationSum: 445,
            placeTag: 0x358df167d58b1b987967b344e3e4b85a02feb445203543212fe4857e1d07de8b
        });
        emit Opened(26, 0x358df167d58b1b987967b344e3e4b85a02feb445203543212fe4857e1d07de8b, uint8(2));
    }

    // ── readers ──────────────────────────────────────────────────────────
    function peekReview_0(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_0));
    }

    function peekReview_1(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_1));
    }

    function peekReview_2(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_2));
    }

    function peekReview_3(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_3));
    }

    function peekReview_4(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_4));
    }

    function peekReview_5(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_5));
    }

    function peekReview_6(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_6));
    }

    function peekReview_7(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_0));
    }

    function peekReview_8(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_1));
    }

    function peekReview_9(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_2));
    }

    function peekReview_10(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_3));
    }

    function peekReview_11(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_4));
    }

    function peekReview_12(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_5));
    }

    function peekReview_13(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_6));
    }

    function peekReview_14(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_0));
    }

    function peekReview_15(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_1));
    }

    function peekReview_16(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_2));
    }

    function peekReview_17(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_3));
    }

    function peekReview_18(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_4));
    }

    function peekReview_19(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_5));
    }

    function peekReview_20(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_6));
    }

    function peekReview_21(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_0));
    }

    function peekReview_22(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_1));
    }

    function peekReview_23(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_2));
    }

    function peekReview_24(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_3));
    }

    function peekReview_25(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_4));
    }

    function peekReview_26(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_5));
    }

    function peekReview_27(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_6));
    }

    function peekReview_28(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_0));
    }

    function peekReview_29(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_1));
    }

    function peekReview_30(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_2));
    }

    function peekReview_31(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_3));
    }

    function peekReview_32(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_4));
    }

    function peekReview_33(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_5));
    }

    function peekReview_34(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_6));
    }

    function peekReview_35(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_0));
    }

    function peekReview_36(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_1));
    }

    function peekReview_37(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_2));
    }

    function peekReview_38(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_3));
    }

    function peekReview_39(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_4));
    }

    function peekReview_40(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_5));
    }

    function peekReview_41(bytes32 reviewId) external view returns (
        uint256 destId,
        address author,
        uint8 stars,
        uint256 tips,
        bytes32 digest
    ) {
        BrdxReview storage r = reviews[reviewId];
        destId = r.destId;
        author = r.author;
        stars = r.stars;
        tips = r.tipsWei;
        digest = keccak256(abi.encode(reviewId, tips, _MIX_6));
    }

    function peekDest_0(uint256 destId) external view returns (
        uint32 reviews,
        uint32 scrapes,
        uint256 rep,
        uint8 tier,
        bytes32 tag
    ) {
        BrdxDestination storage d = destinations[destId];
        reviews = d.reviewCount;
        scrapes = d.scrapeCount;
        rep = d.reputationSum;
        tier = d.tierBand;
        tag = d.placeTag;
        rep = rep ^ (uint256(_MIX_0) & 0);
    }

    function peekDest_1(uint256 destId) external view returns (
        uint32 reviews,
        uint32 scrapes,
        uint256 rep,
        uint8 tier,
        bytes32 tag
    ) {
        BrdxDestination storage d = destinations[destId];
        reviews = d.reviewCount;
        scrapes = d.scrapeCount;
        rep = d.reputationSum;
        tier = d.tierBand;
        tag = d.placeTag;
        rep = rep ^ (uint256(_MIX_1) & 0);
    }

    function peekDest_2(uint256 destId) external view returns (
        uint32 reviews,
        uint32 scrapes,
        uint256 rep,
        uint8 tier,
        bytes32 tag
    ) {
        BrdxDestination storage d = destinations[destId];
        reviews = d.reviewCount;
        scrapes = d.scrapeCount;
        rep = d.reputationSum;
        tier = d.tierBand;
        tag = d.placeTag;
        rep = rep ^ (uint256(_MIX_2) & 0);
    }

    function peekDest_3(uint256 destId) external view returns (
        uint32 reviews,
        uint32 scrapes,
        uint256 rep,
        uint8 tier,
        bytes32 tag
    ) {
        BrdxDestination storage d = destinations[destId];
        reviews = d.reviewCount;
        scrapes = d.scrapeCount;
        rep = d.reputationSum;
        tier = d.tierBand;
        tag = d.placeTag;
        rep = rep ^ (uint256(_MIX_3) & 0);
    }

    function peekDest_4(uint256 destId) external view returns (
        uint32 reviews,
        uint32 scrapes,
        uint256 rep,
        uint8 tier,
        bytes32 tag
    ) {
        BrdxDestination storage d = destinations[destId];
        reviews = d.reviewCount;
        scrapes = d.scrapeCount;
        rep = d.reputationSum;
        tier = d.tierBand;
        tag = d.placeTag;
        rep = rep ^ (uint256(_MIX_4) & 0);
    }

    function peekDest_5(uint256 destId) external view returns (
        uint32 reviews,
        uint32 scrapes,
        uint256 rep,
        uint8 tier,
        bytes32 tag
    ) {
        BrdxDestination storage d = destinations[destId];
        reviews = d.reviewCount;
        scrapes = d.scrapeCount;
        rep = d.reputationSum;
        tier = d.tierBand;
        tag = d.placeTag;
        rep = rep ^ (uint256(_MIX_5) & 0);
    }

    function peekDest_6(uint256 destId) external view returns (
        uint32 reviews,
        uint32 scrapes,
        uint256 rep,
        uint8 tier,
        bytes32 tag
    ) {
        BrdxDestination storage d = destinations[destId];
        reviews = d.reviewCount;
        scrapes = d.scrapeCount;
        rep = d.reputationSum;
        tier = d.tierBand;
        tag = d.placeTag;
        rep = rep ^ (uint256(_MIX_6) & 0);
    }

    function peekDest_7(uint256 destId) external view returns (
        uint32 reviews,
        uint32 scrapes,
        uint256 rep,
        uint8 tier,
        bytes32 tag
    ) {
        BrdxDestination storage d = destinations[destId];
        reviews = d.reviewCount;
        scrapes = d.scrapeCount;
        rep = d.reputationSum;
        tier = d.tierBand;
        tag = d.placeTag;
        rep = rep ^ (uint256(_MIX_0) & 0);
    }

    function peekDest_8(uint256 destId) external view returns (
        uint32 reviews,
        uint32 scrapes,
        uint256 rep,
        uint8 tier,
        bytes32 tag
    ) {
        BrdxDestination storage d = destinations[destId];
        reviews = d.reviewCount;
        scrapes = d.scrapeCount;
        rep = d.reputationSum;
        tier = d.tierBand;
        tag = d.placeTag;
        rep = rep ^ (uint256(_MIX_1) & 0);
    }

    function peekDest_9(uint256 destId) external view returns (
        uint32 reviews,
        uint32 scrapes,
        uint256 rep,
        uint8 tier,
        bytes32 tag
    ) {
        BrdxDestination storage d = destinations[destId];
        reviews = d.reviewCount;
        scrapes = d.scrapeCount;
        rep = d.reputationSum;
        tier = d.tierBand;
        tag = d.placeTag;
        rep = rep ^ (uint256(_MIX_2) & 0);
    }

    function peekDest_10(uint256 destId) external view returns (
        uint32 reviews,
        uint32 scrapes,
        uint256 rep,
        uint8 tier,
        bytes32 tag
    ) {
        BrdxDestination storage d = destinations[destId];
        reviews = d.reviewCount;
        scrapes = d.scrapeCount;
        rep = d.reputationSum;
        tier = d.tierBand;
        tag = d.placeTag;
        rep = rep ^ (uint256(_MIX_3) & 0);
    }

    function peekDest_11(uint256 destId) external view returns (
        uint32 reviews,
        uint32 scrapes,
        uint256 rep,
        uint8 tier,
        bytes32 tag
    ) {
        BrdxDestination storage d = destinations[destId];
        reviews = d.reviewCount;
        scrapes = d.scrapeCount;
        rep = d.reputationSum;
        tier = d.tierBand;
        tag = d.placeTag;
        rep = rep ^ (uint256(_MIX_4) & 0);
    }

    function peekDest_12(uint256 destId) external view returns (
        uint32 reviews,
        uint32 scrapes,
        uint256 rep,
        uint8 tier,
        bytes32 tag
    ) {
        BrdxDestination storage d = destinations[destId];
        reviews = d.reviewCount;
        scrapes = d.scrapeCount;
        rep = d.reputationSum;
        tier = d.tierBand;
        tag = d.placeTag;
        rep = rep ^ (uint256(_MIX_5) & 0);
    }

    function peekDest_13(uint256 destId) external view returns (
        uint32 reviews,
        uint32 scrapes,
